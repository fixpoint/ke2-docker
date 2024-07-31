#!/bin/bash
#
# PostgreSQL/Pgpool-II クラスタ構築用のスクリプト
# 構成:
#  - postgresql 16 以上
#  - pgpool 4.5 以上
#
# 対象OS:
#  - AlmaLinux 9
#  - RockyLinux 9

set -eu  # 未定義変数のチェック、コマンドエラー時は処理中断

: ${CLUSTER_HOSTS:?Undefined environment variable. Example: export CLUSTER_HOSTS="'server1 server2 server3'"}
: ${CLUSTER_VIP:?Undefined environment variable. Example: export CLUSTER_VIP=10.20.0.1}

: ${IF_NAME:=$(ip -brief link show | grep -E -v '(LOOPBACK|DOWN)' | head -1 | (read ifname _rem; echo $ifname))}
: ${IF_PREFIX:=$(ip -brief -f inet addr show dev ${IF_NAME} primary | (read ifname status addr _rem; echo ${addr#*/}))}
: ${HOST_NAME:=$(hostname)}

: ${PG_USER:=postgres}
: ${PG_PASS:=${PG_USER}}
: ${PG_REPL_USER:=repl}
: ${PG_REPL_PASS:=${PG_REPL_USER}}
: ${PG_POOL_USER:=pgpool}
: ${PG_POOL_PASS:=${PG_POOL_USER}}
: ${PG_KOMPIRA_USER:=kompira}
: ${PG_KOMPIRA_PASS:=${PG_KOMPIRA_USER}}
: ${PG_POOL_KEY:=ke2pgpoolkey}
: ${PG_KOMPIRA_DB:=kompira}

# postgresql のアーカイブディレクトリ
: ${POSTGRES_ARCHIVE_DIR:=/var/lib/pgsql/archivedir}

# postgresq にカスタム設定するパラメータ
: ${POSTGRES_MAX_CONNECTIONS:=256}
: ${POSTGRES_WAL_LEVEL:=replica}
: ${POSTGRES_WAL_LOG_HINTS:=on}
: ${POSTGRES_ARCHIVE_MODE:=off}
: ${POSTGRES_MAX_WAL_SENDERS:=10}
: ${POSTGRES_MAX_REPLICATION_SLOTS:=10}

# pgpool の設定ファイルパス
: ${PGPOOL_CONF_PATH:=/etc/pgpool-II}

# pgpool にカスタム設定するパラメータ
: ${PGPOOL_NUM_INIT_CHILDREN:=64}
: ${PGPOOL_LOAD_BALANCE_MODE:=off}
: ${PGPOOL_USE_WATCHDOG:=on}

# hba.conf/pool_hba.conf に設定する接続許可するネットワークアドレス
# postgresql/pgpool は同じネットワーク (samenet) に所属する前提
# 接続元の kompira が postgres/pgpool と別ネットワークに配置される場合は
# 環境変数 HBA_KOMPIRA_ADDRESS=10.10.0.0/16 などと指定すること
: ${HBA_CLUSTER_ADDRESS:=samenet}
: ${HBA_KOMPIRA_ADDRESS:=samenet}

#
# root ユーザに切り替える
#
if [[ ${USER} != "root" ]]; then
    echo "root ユーザではありません。sudo 権限で root ユーザに変更します"
    sudo -E su -m -c ${0}
    exit $?
fi

check_node_id()
{
    #
    # Pgpool-II ノードIDの設定
    #
    local i=0
    for host in ${CLUSTER_HOSTS}; do
        if [[ ${host} = ${HOST_NAME} ]]; then
            NODE_ID=${i}
            break
        fi
        : $((++i))
    done
    if [[ ! -v NODE_ID ]]; then
        echo "ホスト名 ${HOST_NAME} が" '$CLUSTER_HOSTS に含まれていません'
        exit 1
    fi
    : ${IS_PRIMARY_MODE:=$((($NODE_ID==0))&&echo true||echo false)}  # プライマリモードでセットアップを行う場合は true をセットする
}

install_packages_on_rhel9()
{
    # PostgreSQL / Pgpool-II のインストール (RHEL9)
    # dnf update -y

    # PostgreSQL コミュニティのリポジトリから PostgreSQL バージョン16 をインストールする
    # [備考] postgresql16-contrib パッケージは、pgcrypto 拡張に必要となる
    #
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    dnf -qy module disable postgresql
    dnf install -y postgresql16-server postgresql16-contrib

    # AlmaLinux 9 にインストールする場合、libmemcached が無いと言って怒られるので、事前に各ホスト上で以下を実行しておく必要がある。
    #
    dnf config-manager --set-enabled crb

    # Pgpool-II関連のパッケージはPostgreSQLコミュニティのリポジトリにもあるため、
    # PostgreSQLのリポジトリパッケージがすでにインストールされている場合は、
    # PostgreSQLコミュニティのリポジトリからPgpool-IIをインストールしないように
    # /etc/yum.repos.d/pgdg-redhat-all.repoにexclude設定を行う。
    #
    dnf config-manager --setopt 'pgdg*.exclude=pgpool*' --save

    # pgpool-II をインストールする
    #
    dnf install -y https://www.pgpool.net/yum/rpms/4.5/redhat/rhel-9-x86_64/pgpool-II-release-4.5-1.noarch.rpm
    dnf install -y pgpool-II-pg16-*
}

setup_postgres()
{
    #
    # すべてのサーバにてWALを格納するディレクトリ /var/lib/pgsql/archivedir を事前に作成する。
    #
    su - postgres -c "mkdir -p ${POSTGRES_ARCHIVE_DIR}"
    chmod 700 ${POSTGRES_ARCHIVE_DIR}

    # PGDATA 環境変数を postgres ユーザ以外からも参照できるようにしておく
    PGDATA=$(su - postgres -c 'echo ${PGDATA}')
    PGHOME=$(dirname $(dirname $(readlink -f $(which psql))))

    # 再セットアップ時は postgresl を停止させる
    if su - postgres -c "${PGHOME}/bin/pg_ctl status -D ${PGDATA}"; then
        su - postgres -c "${PGHOME}/bin/pg_ctl stop -D ${PGDATA}"
    fi

    #
    # プライマリサーバで PostgreSQL の初期化を行う
    #
    if ${IS_PRIMARY_MODE}; then
        #
        # PGDATA/PG_VERSION が無い場合 initdb を実施する
        # TODO: 強制的に初期化するモードを追加する
        #
        if [ ! -f $PGDATA/PG_VERSION ]; then
            postgresql-16-setup initdb
        fi

        #
        # 設定ファイル $PGDATA/postgresql.conf を以下のように編集する。
        # ---
        #   pg_rewindを使うためにwal_log_hintsを有効にする。
        #   プライマリが後でスタンバイになる可能性があるので、hot_standby = onにする。
        #
        cp -a -f ${PGDATA}/postgresql.conf ${PGDATA}/postgresql.conf.old
        (
            sed -re "/^# KE2-BEGIN/,/^# KE2-END/d" ${PGDATA}/postgresql.conf.old
            cat <<EOF
# KE2-BEGIN: ke2 custom settings
listen_addresses = '*'
max_connections = ${POSTGRES_MAX_CONNECTIONS}
wal_level = ${POSTGRES_WAL_LEVEL}
wal_log_hints = ${POSTGRES_WAL_LOG_HINTS}
archive_mode = ${POSTGRES_ARCHIVE_MODE}
archive_command = 'cp "%p" "${POSTGRES_ARCHIVE_DIR}/%f"'
max_wal_senders = ${POSTGRES_MAX_WAL_SENDERS}
max_replication_slots = ${POSTGRES_MAX_REPLICATION_SLOTS}
hot_standby = on
# KE2-END
EOF
        ) > ${PGDATA}/postgresql.conf

        #
        # プライマリサーバで PostgreSQL を起動する
        #
        su - postgres -c "${PGHOME}/bin/pg_ctl start -D ${PGDATA}"

        #
        # PostgreSQL ユーザを作成する
        #
        #  - repl/repl: PostgreSQL のレプリケーション専用
        #  - pgpool/pgpool: Pgpool-IIのレプリケーション遅延チェック(sr_check_user)、 ヘルスチェック専用ユーザ(health_check_user)。pg_monitorグループに所属させる
        #  - postgres/postgres: オンラインリカバリの実行ユーザ
        #  - kompira/kompira: Kompira アクセス用ユーザ (スーパーユーザ権限が必要)
        #
        if [ $(sudo -i -u postgres psql -t -c "SELECT EXISTS (SELECT * FROM pg_user WHERE usename = '${PG_POOL_USER}');") != t ]; then
            sudo -i -u postgres createuser -e ${PG_POOL_USER}
        fi
        if [ $(sudo -i -u postgres psql -t -c "SELECT EXISTS (SELECT * FROM pg_user WHERE usename = '${PG_REPL_USER}');") != t ]; then
            sudo -i -u postgres createuser -e ${PG_REPL_USER} --replication
        fi
        if [ $(sudo -i -u postgres psql -t -c "SELECT EXISTS (SELECT * FROM pg_user WHERE usename = '${PG_KOMPIRA_USER}');") != t ]; then
            sudo -i -u postgres createuser -e ${PG_KOMPIRA_USER} --createdb
        fi
        sudo -i -u postgres psql -c "ALTER ROLE ${PG_USER} PASSWORD '${PG_PASS}'"
        sudo -i -u postgres psql -c "ALTER ROLE ${PG_REPL_USER} PASSWORD '${PG_REPL_PASS}'"
        sudo -i -u postgres psql -c "ALTER ROLE ${PG_POOL_USER} PASSWORD '${PG_POOL_PASS}'"
        sudo -i -u postgres psql -c "ALTER ROLE ${PG_KOMPIRA_USER} PASSWORD '${PG_KOMPIRA_PASS}'"
        sudo -i -u postgres psql -c "GRANT pg_monitor TO ${PG_POOL_USER}"
        #
        # Kompira用データベースを作成する
        #
        if ! sudo -i -u postgres psql -d ${PG_KOMPIRA_DB} -c \\q; then
            sudo -i -u postgres createdb --owner=${PG_KOMPIRA_USER} --encoding=utf8 ${PG_KOMPIRA_DB}
        fi

        #
        # Pgpool-IIサーバとPostgreSQLバックエンドサーバが同じサブネットワークにあることを想定し、
        # 各ユーザがscram-sha-256認証方式で接続するように、pg_hba.confを編集する
        #
        cp -a -f ${PGDATA}/pg_hba.conf ${PGDATA}/pg_hba.conf.old
        (
            sed -re "/^# KE2-BEGIN/,/^# KE2-END/d" ${PGDATA}/pg_hba.conf.old
            cat <<EOF
# KE2-BEGIN: ke2 custom settings
host    all             ${PG_POOL_USER}          ${HBA_CLUSTER_ADDRESS}                 scram-sha-256
host    all             ${PG_USER}        ${HBA_CLUSTER_ADDRESS}                 scram-sha-256
host    replication     all             ${HBA_CLUSTER_ADDRESS}                 scram-sha-256
host    ${PG_KOMPIRA_DB}         ${PG_KOMPIRA_USER}         ${HBA_KOMPIRA_ADDRESS}                 scram-sha-256
# KE2-END
EOF
        ) > ${PGDATA}/pg_hba.conf

        #
        # pg_hba.conf を修正したので、PostgreSQL を再起動する
        #
        su - postgres -c "${PGHOME}/bin/pg_ctl restart -D ${PGDATA}"
    else
        #
        # スタンバイサーバは、後ほどオンラインリカバリ機能を用いてセットアップする
        #
        :
    fi
    #
    # .pgpassの作成
    #
    # パスワード入力なしで、ストリーミングレプリケーションやpg_rewindを実
    # 行するために、すべてのサーバでpostgresユーザのホームディレクトリ
    # /var/lib/pgsqlに.pgpassを作成し、パーミッションを600に設定しておく
    #
    PG_PASS_FILE=/var/lib/pgsql/.pgpass
    for host in ${CLUSTER_HOSTS}; do
        su - postgres -c "grep -qs '${host}:5432:replication:${PG_REPL_USER}:' ${PG_PASS_FILE} || echo '${host}:5432:replication:${PG_REPL_USER}:${PG_REPL_PASS}' >> ${PG_PASS_FILE}"
        su - postgres -c "grep -qs '${host}:5432:postgres:${PG_USER}:' ${PG_PASS_FILE} || echo '${host}:5432:postgres:${PG_USER}:${PG_PASS}' >> ${PG_PASS_FILE}"
    done
    chmod 600 /var/lib/pgsql/.pgpass
}

setup_firewall()
{
    #
    # firewall の設定
    #
    # ポート番号	用途	備考
    # 9999	Pgpool-IIが接続を受け付けるポート番号
    # 9898	PCPプロセスが接続を受け付けるポート番号
    # 9000	Watchdogが接続を受け付けるポート番号
    # 9694	Watchdogのハートビート信号を受信するUDPポート番号
    #
    firewall-cmd --permanent --zone=public --add-service=postgresql
    firewall-cmd --permanent --zone=public --add-port=9999/tcp --add-port=9898/tcp --add-port=9000/tcp  --add-port=9694/udp
    firewall-cmd --reload
}

setup_pgpool()
{
    #
    # pgpool_node_idファイルの作成
    #
    # Pgpool-II 4.2以降、すべての設定パラメータがすべてのホストで同一にな
    # りました。 Watchdog機能が有効になっている場合、どの設定がどのホスト
    # であるかを区別するには、 pgpool_node_idファイルの設定が必要になりま
    # す。 pgpool_node_idファイルを作成し、 そのファイルにpgpool(watchdog)
    # ホストを識別するためのノード番号(0、1、2など)を追加します。
    #
    echo ${NODE_ID} > ${PGPOOL_CONF_PATH}/pgpool_node_id

    #
    # PCP接続認証の設定
    #
    # PCPコマンドを使用するために、username:encryptedpassword形式のPCPユーザ名とmd5暗号化パスワードをpcp.confに登録する
    #
    local PCP_CONF_FILE=${PGPOOL_CONF_PATH}/pcp.conf
    grep -qs "${PG_POOL_USER}:" ${PCP_CONF_FILE} || echo "${PG_POOL_USER}:$(pg_md5 ${PG_POOL_PASS})" >> ${PCP_CONF_FILE}

    #
    # Pgpool-II の設定
    #
    # RPMからインストールした場合、Pgpool-IIの設定ファイル pgpool.confは/etc/pgpool-IIにあります。
    #
    # Pgpool-II 4.2以降、すべての設定パラメーターがすべてのホストで同一に
    # なったので、 どれか一つのノード上でpgpool.confを編集し、 編集した
    # pgpool.confファイルを他のpgpoolノードにコピーすれば良いです。
    #
    local PGPOOL_KE2_BACKENDS_CONF=pgpool.ke2-backends.conf
    cp -a -f ${PGPOOL_CONF_PATH}/pgpool.conf ${PGPOOL_CONF_PATH}/pgpool.conf.old
    (
        sed -re "/^# KE2-BEGIN/,/^# KE2-END/d" ${PGPOOL_CONF_PATH}/pgpool.conf.old
        cat <<EOF
# KE2-BEGIN: ke2 custom settings
listen_addresses = '*'
pcp_listen_addresses = '*'
enable_pool_hba = on
num_init_children = ${PGPOOL_NUM_INIT_CHILDREN}
log_rotation_size = 10MB 
load_balance_mode = ${PGPOOL_LOAD_BALANCE_MODE}
sr_check_user = '${PG_POOL_USER}'
follow_primary_command = '${PGPOOL_CONF_PATH}/follow_primary.sh %d %h %p %D %m %H %M %P %r %R'
health_check_period = 5
health_check_timeout = 30
health_check_user = '${PG_POOL_USER}'
health_check_max_retries = 3
failover_command = '${PGPOOL_CONF_PATH}/failover.sh %d %h %p %D %m %H %M %P %r %R %N %S'
recovery_user = '${PG_USER}'
recovery_1st_stage_command = 'recovery_1st_stage'
use_watchdog = ${PGPOOL_USE_WATCHDOG}
delegate_ip = '${CLUSTER_VIP}'
if_up_cmd = '/usr/bin/sudo /sbin/ip addr add \$_IP_\$/${IF_PREFIX} dev ${IF_NAME} label ${IF_NAME}:0'
if_down_cmd = '/usr/bin/sudo /sbin/ip addr del \$_IP_\$/${IF_PREFIX} dev ${IF_NAME}'
arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U \$_IP_\$ -w 1 -I ${IF_NAME}'
wd_escalation_command = '${PGPOOL_CONF_PATH}/escalation.sh'
include '${PGPOOL_KE2_BACKENDS_CONF}'
# KE2-END
EOF
    ) > ${PGPOOL_CONF_PATH}/pgpool.conf

    #
    # また、バックエンド情報を前述のke2-swarm1、ke2-swarm2 及びke2-swarm3
    # の設定に従って設定しておきます。 複数バックエンドノードを定義する場
    # 合、以下のbackend_*などのパラメータ名の 末尾にノードIDを表す数字を付
    # 加することで複数のバックエンドを指定することができます
    #
    echo -n > ${PGPOOL_CONF_PATH}/${PGPOOL_KE2_BACKENDS_CONF}
    local i=0
    for host in ${CLUSTER_HOSTS}; do
        cat >> ${PGPOOL_CONF_PATH}/${PGPOOL_KE2_BACKENDS_CONF} <<EOF
# - Backend Connection Settings for ${host} -
backend_hostname${i} = '${host}'
backend_port${i} = 5432
backend_weight${i} = 1
backend_data_directory${i} = '${PGDATA}'
backend_flag${i} = 'ALLOW_TO_FAILOVER'
backend_application_name${i} = '${host}'
# - Watchdog communication Settings for ${host} -
hostname${i} = '${host}'
wd_port${i} = 9000
pgpool_port${i} = 9999
# - Lifecheck Settings for ${host} -
heartbeat_hostname${i} = '${host}'
heartbeat_port${i} = 9694
heartbeat_device${i} = ''

EOF
        : $((++i))
    done
    chown postgres:postgres ${PGPOOL_CONF_PATH}/${PGPOOL_KE2_BACKENDS_CONF}

    #
    # サンプルスクリプトfailover.sh及び follow_primary.shは
    # /etc/pgpool-II/sample_scripts配下にインストールされていますので、こ
    # れらのファイルをコピーして作成します。
    #
    cp -p ${PGPOOL_CONF_PATH}/sample_scripts/failover.sh.sample ${PGPOOL_CONF_PATH}/failover.sh
    cp -p ${PGPOOL_CONF_PATH}/sample_scripts/follow_primary.sh.sample ${PGPOOL_CONF_PATH}/follow_primary.sh
    cp -p ${PGPOOL_CONF_PATH}/sample_scripts/escalation.sh.sample ${PGPOOL_CONF_PATH}/escalation.sh
    chown postgres:postgres ${PGPOOL_CONF_PATH}/{failover.sh,follow_primary.sh,escalation.sh}

    #
    # escalation.sh の サーバのホスト名、仮想IP、仮想IPを設定するネットワークインターフェースを修正する
    #
    sed -i.old -f- ${PGPOOL_CONF_PATH}/escalation.sh <<EOF
s/^PGPOOLS=.*/PGPOOLS=(${CLUSTER_HOSTS})/
s/^VIP=.*/VIP=${CLUSTER_VIP}/
s/^DEVICE=.*/DEVICE=${IF_NAME}/
s|/24 dev|/${IF_PREFIX} dev|
EOF

    #
    # 前述のfollow_primary.shのスクリプトでパスワード入力なしでPCPコマンド
    # を実行できるように、すべてのサーバでPgpool-IIの起動ユーザのホームディ
    # レクトリに.pcppassを作成します。
    #
    su - postgres -c "echo 'localhost:9898:${PG_POOL_USER}:${PG_POOL_PASS}' > ~/.pcppass && chmod 600 ~/.pcppass"

    if ${IS_PRIMARY_MODE}; then
        #
        # オンラインリカバリ用のサンプルスクリプトrecovery_1st_stage 及び
        # pgpool_remote_startは ${PGPOOL_CONF_PATH}/sample_scripts配下にインストー
        # ルされていますので、 これらのファイルをプライマリサーバ(ke2-swarm1)
        # のデータベースクラスタ配下に配置します。
        #
        su - postgres -c "cp -p ${PGPOOL_CONF_PATH}/sample_scripts/recovery_1st_stage.sample ${PGDATA}/recovery_1st_stage"
        su - postgres -c "cp -p ${PGPOOL_CONF_PATH}/sample_scripts/pgpool_remote_start.sample ${PGDATA}/pgpool_remote_start"
        # ログが文字化けしないよう、LANG 環境変数をセットして pg_ctl を起動する
        su - postgres -c "sed -i -e 's|\$PGHOME/bin/pg_ctl|LANG=\${LANG} \$PGHOME/bin/pg_ctl|' ${PGDATA}/pgpool_remote_start"
        #
        # オンラインリカバリ機能を使用するには、pgpool_recovery、
        # pgpool_remote_start、pgpool_switch_xlogという関数が必要になるので、
        # ke2-swarm1のtemplate1にpgpool_recoveryをインストールしておきます。
        #
        sudo -i -u postgres psql template1 -c "CREATE EXTENSION IF NOT EXISTS pgpool_recovery"
    fi

    #
    # Pgpool-IIのクライアント認証の設定ファイルは pool_hba.confと呼ば
    # れ、RPMパッケージからインストールする場合、 デフォルトでは
    # /etc/pgpool-II配下にインストールされます。 
    #
    # pool_hba.confのフォーマットはPostgreSQLの pg_hba.confとほとんど
    # 同じです。 pgpoolとpostgresユーザの認証方式をscram-sha-256に設定
    # します。 この設定例では、Pgpool-IIに接続しているアプリケーション
    # が同じサブネット内にあると想定しています。
    #
    cp -a -f ${PGPOOL_CONF_PATH}/pool_hba.conf ${PGPOOL_CONF_PATH}/pool_hba.conf.old
    (
        sed -re "/^# KE2-BEGIN/,/^# KE2-END/d" ${PGPOOL_CONF_PATH}/pool_hba.conf.old
        cat <<EOF
# KE2-BEGIN: ke2 custom settings
host    all         ${PG_POOL_USER}           ${HBA_CLUSTER_ADDRESS}          scram-sha-256
host    all         ${PG_USER}         ${HBA_CLUSTER_ADDRESS}          scram-sha-256
host    ${PG_KOMPIRA_DB}     ${PG_KOMPIRA_USER}          ${HBA_KOMPIRA_ADDRESS}          scram-sha-256
# KE2-END
EOF
    ) > ${PGPOOL_CONF_PATH}/pool_hba.conf

    #
    # Pgpool-IIのクライアント認証で用いるデフォルトのパスワードファイル名
    # はpool_passwdです。 scram-sha-256認証を利用する場合、Pgpool-IIはそれ
    # らのパスワードを復号化するために復号鍵が必要となります。 全サーバで
    # 復号鍵ファイルをPgpool-IIの起動ユーザpostgres (Pgpool-II 4.0以前のバー
    # ジョンでは root) のホームディレクトリ配下に作成します。
    #
    su - postgres -c "echo '${PG_POOL_KEY}' > ~/.pgpoolkey && chmod 600 ~/.pgpoolkey"
    #
    # pg_enc -m -k /path/to/.pgpoolkey -u username -pを実行すると、ユーザ
    # 名とAES256で暗号化したパスワードのエントリがpool_passwdに登録されま
    # す。 pool_passwd がまだ存在しなければ、pgpool.confと同じディレクトリ
    # 内に作成されます。
    #
    su - postgres -c "cat | pg_enc -m -k ~/.pgpoolkey -i /dev/stdin" <<EOF
${PG_POOL_USER}:${PG_POOL_PASS}
${PG_USER}:${PG_PASS}
${PG_KOMPIRA_USER}:${PG_KOMPIRA_PASS}
EOF

    #
    # すべてのサーバでログファイルを格納するディレクトリを作成します。
    # (インストールした時点で作成されているかもしれない)
    #
    mkdir -p /var/log/pgpool_log
    chown postgres:postgres /var/log/pgpool_log
}

check_node_id
install_packages_on_rhel9
setup_postgres
setup_firewall
setup_pgpool

echo "==============================================================================="
echo " PostgreSQL/Pgpool-II のセットアップが終了しました。"
echo ""
echo " すべてのホストで setup_pgpool.sh の実行が終了した後、"
echo " 各ホスト上で改めて CLUSTER_HOSTS を指定して setup_pgssh.sh を実行してください。"
echo
echo "$ sudo CLUSTER_HOSTS=\"$CLUSTER_HOSTS\" ./setup_pgssh.sh"
echo "==============================================================================="
