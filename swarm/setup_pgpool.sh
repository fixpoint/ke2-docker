#!/bin/bash

#
# PostgreSQL/Pgpool-II クラスタ構築用のスクリプト
#
# 対象OS: AlmaLinux 9
#

set -eu  # 未定義変数のチェック、コマンドエラー時は処理中断

: ${CLUSTER_HOSTS:=ke2dev-swarm1 ke2dev-swarm2 ke2dev-swarm3}
: ${CLUSTER_VIP:=10.20.1.100}
: ${IF_NAME:=ens33}
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

#
# root ユーザに切り替える
#
if [[ ${USER} != "root" ]]; then
    echo "root ユーザではありません。sudo 権限で root ユーザに変更します"
    sudo -E su -m -c ${0}
    exit $?
fi
: ${LOGIN_USER:=${SUDO_USER}}

#
# Pgpool-II ノードIDの設定
#
i=0
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

#
# 必要なツール類のセットアップ
#
dnf update -y
dnf install -y patch

#
# PostgreSQL コミュニティのリポジトリから PostgreSQL バージョン16 をインストールする
#
# [備考] postgresql16-contrib パッケージは、pgcrypto 拡張に必要となる
#
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
dnf install -y postgresql16-server postgresql16-contrib

#
# AlmaLinux 9 にインストールする場合、libmemcached が無いと言って怒られるので、事前に各ホスト上で以下を実行しておく必要がある。
#
dnf config-manager --set-enabled crb

#
# Pgpool-II関連のパッケージはPostgreSQLコミュニティのリポジトリにもあるため、
# PostgreSQLのリポジトリパッケージがすでにインストールされている場合は、
# PostgreSQLコミュニティのリポジトリからPgpool-IIをインストールしないように
# /etc/yum.repos.d/pgdg-redhat-all.repoにexclude設定を行う。
#
patch -N /etc/yum.repos.d/pgdg-redhat-all.repo <<'EOF' || echo 'pgdg-redhat-all.repo のパッチ適用に失敗しました'
--- /etc/yum.repos.d/pgdg-redhat-all.repo	2024-04-10 16:00:02.000000000 +0900
+++ pgdg-redhat-all.repo	2024-06-05 08:27:26.531561739 +0900
@@ -8,6 +8,7 @@
 name=PostgreSQL common RPMs for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/common/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
@@ -41,6 +42,7 @@
 name=PostgreSQL 16 for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
@@ -49,6 +51,7 @@
 name=PostgreSQL 15 for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
@@ -57,6 +60,7 @@
 name=PostgreSQL 14 for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
@@ -65,6 +69,7 @@
 name=PostgreSQL 13 for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
@@ -73,6 +78,7 @@
 name=PostgreSQL 12 for RHEL / Rocky / AlmaLinux $releasever - $basearch
 baseurl=https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-$releasever-$basearch
 enabled=1
+exclude=pgpool*
 gpgcheck=1
 gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
 repo_gpgcheck = 1
EOF

#
# pgpool-II をインストールする
#
dnf install -y https://www.pgpool.net/yum/rpms/4.5/redhat/rhel-9-x86_64/pgpool-II-release-4.5-1.noarch.rpm
dnf install -y pgpool-II-pg16-*

#
# すべてのサーバにてWALを格納するディレクトリ/var/lib/pgsql/archivedirを事前に作成する。
#
PGPOOL_ARCHIVE_DIR=/var/lib/pgsql/archivedir
su - postgres -c "mkdir -p ${PGPOOL_ARCHIVE_DIR}"

PGDATA=$(su - postgres -c 'echo ${PGDATA}') # PGDATA 環境変数を postgres ユーザ以外からも参照できるようにしておく
#
# プライマリサーバで PostgreSQL の初期化を行う
#
if ${IS_PRIMARY_MODE}; then
    su - postgres -c '/usr/pgsql-16/bin/initdb -D ${PGDATA}'
    #
    # 設定ファイル $PGDATA/postgresql.conf を以下のように編集する。
    # ---
    #   pg_rewindを使うためにwal_log_hintsを有効にする。
    #   プライマリが後でスタンバイになる可能性があるので、hot_standby = onにする。
    #
    patch -N ${PGDATA}/postgresql.conf <<'EOF'
--- postgresql.conf	2024-06-05 09:40:50.969136122 +0900
+++ /var/lib/pgsql/16/data/postgresql.conf	2024-06-05 09:43:12.789063174 +0900
@@ -57,7 +57,7 @@
 
 # - Connection Settings -
 
-#listen_addresses = 'localhost'		# what IP address(es) to listen on;
+listen_addresses = '*'			# what IP address(es) to listen on;
 					# comma-separated list of addresses;
 					# defaults to 'localhost'; use '*' for all
 					# (change requires restart)
@@ -208,7 +208,7 @@
 
 # - Settings -
 
-#wal_level = replica			# minimal, replica, or logical
+wal_level = replica			# minimal, replica, or logical
 					# (change requires restart)
 #fsync = on				# flush data to disk for crash safety
 					# (turning this off can cause
@@ -223,7 +223,7 @@
 					#   fsync_writethrough
 					#   open_sync
 #full_page_writes = on			# recover from partial page writes
-#wal_log_hints = off			# also do full page writes of non-critical updates
+wal_log_hints = on			# also do full page writes of non-critical updates
 					# (change requires restart)
 #wal_compression = off			# enables compression of full-page writes;
 					# off, pglz, lz4, zstd, or on
@@ -255,12 +255,13 @@
 
 # - Archiving -
 
-#archive_mode = off		# enables archiving; off, on, or always
+archive_mode = on		# enables archiving; off, on, or always
 				# (change requires restart)
 #archive_library = ''		# library to use to archive a WAL file
 				# (empty string indicates archive_command should
 				# be used)
-#archive_command = ''		# command to use to archive a WAL file
+archive_command = 'cp "%p" "/var/lib/pgsql/archivedir/%f"'
+				# command to use to archive a WAL file
 				# placeholders: %p = path of file to archive
 				#               %f = file name only
 				# e.g. 'test ! -f /mnt/server/archivedir/%f && cp %p /mnt/server/archivedir/%f'
@@ -311,9 +312,9 @@
 
 # Set these on the primary and on any standby that will send replication data.
 
-#max_wal_senders = 10		# max number of walsender processes
+max_wal_senders = 10		# max number of walsender processes
 				# (change requires restart)
-#max_replication_slots = 10	# max number of replication slots
+max_replication_slots = 10	# max number of replication slots
 				# (change requires restart)
 #wal_keep_size = 0		# in megabytes; 0 disables
 #max_slot_wal_keep_size = -1	# in megabytes; -1 disables
@@ -336,7 +337,7 @@
 
 #primary_conninfo = ''			# connection string to sending server
 #primary_slot_name = ''			# replication slot on sending server
-#hot_standby = on			# "off" disallows queries during recovery
+hot_standby = on			# "off" disallows queries during recovery
 					# (change requires restart)
 #max_standby_archive_delay = 30s	# max delay before canceling queries
 					# when reading WAL from archive;
EOF
    #
    # プライマリサーバで PostgreSQL を起動する
    #
    su - postgres -c '/usr/pgsql-16/bin/pg_ctl start -D ${PGDATA}'
    #
    # PostgreSQL ユーザを作成する
    #
    #  - repl/repl: PostgreSQL のレプリケーション専用
    #  - pgpool/pgpool: Pgpool-IIのレプリケーション遅延チェック(sr_check_user)、 ヘルスチェック専用ユーザ(health_check_user)。pg_monitorグループに所属させる
    #  - postgres/postgres: オンラインリカバリの実行ユーザ
    #  - kompira/kompira: Kompira アクセス用ユーザ
    #
    createuser -U ${PG_USER} -e ${PG_POOL_USER}
    createuser -U ${PG_USER} -e ${PG_REPL_USER} --replication
    createuser -U ${PG_USER} -e ${PG_KOMPIRA_USER} --createdb
    psql -U ${PG_USER} -c "ALTER ROLE ${PG_USER} PASSWORD '${PG_PASS}'"
    psql -U ${PG_USER} -c "ALTER ROLE ${PG_REPL_USER} PASSWORD '${PG_REPL_PASS}'"
    psql -U ${PG_USER} -c "ALTER ROLE ${PG_POOL_USER} PASSWORD '${PG_POOL_PASS}'"
    psql -U ${PG_USER} -c "ALTER ROLE ${PG_KOMPIRA_USER} PASSWORD '${PG_KOMPIRA_PASS}'"
    psql -U ${PG_USER} -c "GRANT pg_monitor TO ${PG_POOL_USER}"
    #
    # Pgpool-IIサーバとPostgreSQLバックエンドサーバが同じサブネットワークにあることを想定し、
    # 各ユーザがscram-sha-256認証方式で接続するように、pg_hba.confを編集する
    #
    patch -N ${PGDATA}/pg_hba.conf <<'EOF'
--- /var/lib/pgsql/16/data/pg_hba.conf	2024-06-05 10:05:27.026407474 +0900
+++ pg_hba.conf	2024-06-05 10:43:49.540925903 +0900
@@ -124,3 +124,7 @@
 local   replication     all                                     trust
 host    replication     all             127.0.0.1/32            trust
 host    replication     all             ::1/128                 trust
+host    all             pgpool          samenet                 scram-sha-256
+host    all             postgres        samenet                 scram-sha-256
+host    replication     all             samenet                 scram-sha-256
+host    kompira         kompira         samenet                 scram-sha-256
EOF
    #
    # pg_hba.conf を修正したので、PostgreSQL を起動する
    #
    su - postgres -c '/usr/pgsql-16/bin/pg_ctl restart -D ${PGDATA}'
else
    #
    # スタンバイサーバは、後ほどオンラインリカバリ機能を用いてセットアップする
    #
    :
fi
#
# SSH公開鍵認証の設定
#
# 自動フェイルオーバ、オンラインリカバリ機能を利用するには、すべての
# Pgpool-IIノード間でpostgresユーザ（Pgpool-IIのデフォルトの起動ユーザ。
# Pgpool-II 4.0以前、デフォルトの起動ユーザはroot）として双方向にSSH公
# 開鍵認証（パスワードなし）で接続できるように設定する必要があります。
#
# SSH鍵ファイルを作成します。 この設定例では生成される鍵ファイル名はid_rsa_pgpoolとします。
#
SSH_KEYFILE_NAME=id_rsa_pgpool
su - postgres -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
su - postgres -c "(cd .ssh && (yes | ssh-keygen -t rsa -f ${SSH_KEYFILE_NAME} -N ''))"
#
# SELinuxを有効化している場合は、SSH公開鍵認証(パスワードなし)が失敗す
# る可能性があるので、すべてのサーバで以下のコマンドを実行する。
#
su - postgres -c 'restorecon -Rv ~/.ssh'

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

#
# pgpool_node_idファイルの作成
#
# Pgpool-II 4.2以降、すべての設定パラメータがすべてのホストで同一にな
# りました。 Watchdog機能が有効になっている場合、どの設定がどのホスト
# であるかを区別するには、 pgpool_node_idファイルの設定が必要になりま
# す。 pgpool_node_idファイルを作成し、 そのファイルにpgpool(watchdog)
# ホストを識別するためのノード番号(0、1、2など)を追加します。
#
echo ${NODE_ID} > /etc/pgpool-II/pgpool_node_id

#
# PCP接続認証の設定
#
# PCPコマンドを使用するために、username:encryptedpassword形式のPCPユーザ名とmd5暗号化パスワードをpcp.confに登録する
#
PCP_CONF_FILE=/etc/pgpool-II/pcp.conf
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
PGPOOL_CONF_FILE=/etc/pgpool-II/pgpool.conf
patch -N ${PGPOOL_CONF_FILE} <<EOF
--- pgpool.conf.orig	2024-06-06 11:24:23.607627712 +0900
+++ /etc/pgpool-II/pgpool.conf	2024-06-06 13:35:06.475194279 +0900
@@ -32,7 +32,7 @@
 
 # - pgpool Connection Settings -
 
-#listen_addresses = 'localhost'
+listen_addresses = '*'
                                    # what host name(s) or IP address(es) to listen on;
                                    # comma-separated list of addresses;
                                    # defaults to 'localhost'; use '*' for all
@@ -59,7 +59,7 @@
 
 # - pgpool Communication Manager Connection Settings -
 
-#pcp_listen_addresses = 'localhost'
+pcp_listen_addresses = '*'
                                    # what host name(s) or IP address(es) for pcp process to listen on;
                                    # comma-separated list of addresses;
                                    # defaults to 'localhost'; use '*' for all
@@ -105,7 +105,7 @@
 
 # - Authentication -
 
-#enable_pool_hba = off
+enable_pool_hba = on
                                    # Use pool_hba.conf for client authentication
 #pool_passwd = 'pool_passwd'
                                    # File name of pool_passwd for md5 authentication.
@@ -332,7 +332,7 @@
                                         # Automatic rotation of logfiles will
                                         # happen after that (minutes)time.
                                         # 0 disables time based rotation.
-log_rotation_size = 0 
+log_rotation_size = 10MB 
                                         # Automatic rotation of logfiles will
                                         # happen after that much (KB) log output.
                                         # 0 disables size based rotation.
@@ -503,7 +503,7 @@
 #sr_check_period = 10
                                    # Streaming replication check period
                                    # Default is 10s.
-#sr_check_user = 'nobody'
+sr_check_user = 'pgpool'
                                    # Streaming replication check user
                                    # This is necessary even if you disable streaming
                                    # replication delay check by sr_check_period = 0
@@ -531,7 +531,7 @@
 
 # - Special commands -
 
-#follow_primary_command = ''
+follow_primary_command = '/etc/pgpool-II/follow_primary.sh %d %h %p %D %m %H %M %P %r %R'
                                    # Executes this command after main node failover
                                    # Special values:
                                    #   %d = failed node id
@@ -552,13 +552,13 @@
 # HEALTH CHECK GLOBAL PARAMETERS
 #------------------------------------------------------------------------------
 
-#health_check_period = 0
+health_check_period = 5
                                    # Health check period
                                    # Disabled (0) by default
-#health_check_timeout = 20
+health_check_timeout = 30
                                    # Health check timeout
                                    # 0 means no timeout
-#health_check_user = 'nobody'
+health_check_user = 'pgpool'
                                    # Health check user
 #health_check_password = ''
                                    # Password for health check user
@@ -567,7 +567,7 @@
 
 #health_check_database = ''
                                    # Database name for health check. If '', tries 'postgres' frist, 
-#health_check_max_retries = 0
+health_check_max_retries = 3
                                    # Maximum number of times to retry a failed health check before giving up.
 #health_check_retry_delay = 1
                                    # Amount of time to wait (in seconds) between retries.
@@ -594,7 +594,7 @@
 # FAILOVER AND FAILBACK
 #------------------------------------------------------------------------------
 
-#failover_command = ''
+failover_command = '/etc/pgpool-II/failover.sh %d %h %p %D %m %H %M %P %r %R %N %S'
                                    # Executes this command at failover
                                    # Special values:
                                    #   %d = failed node id
@@ -655,14 +655,14 @@
 # ONLINE RECOVERY
 #------------------------------------------------------------------------------
 
-#recovery_user = 'nobody'
+recovery_user = 'postgres'
                                    # Online recovery user
 #recovery_password = ''
                                    # Online recovery password
                                    # Leaving it empty will make Pgpool-II to first look for the
                                    # Password in pool_passwd file before using the empty password
 
-#recovery_1st_stage_command = ''
+recovery_1st_stage_command = 'recovery_1st_stage'
                                    # Executes a command in first stage
 #recovery_2nd_stage_command = ''
                                    # Executes a command in second stage
@@ -690,7 +690,7 @@
 
 # - Enabling -
 
-#use_watchdog = off
+use_watchdog = on
                                     # Activates watchdog
                                     # (change requires restart)
 
@@ -745,7 +745,7 @@
 
 # - Virtual IP control Setting -
 
-#delegate_ip = ''
+delegate_ip = '${CLUSTER_VIP}'
                                     # delegate IP address
                                     # If this is empty, virtual IP never bring up.
                                     # (change requires restart)
@@ -753,17 +753,17 @@
                                     # path to the directory where if_up/down_cmd exists
                                     # If if_up/down_cmd starts with "/", if_cmd_path will be ignored.
                                     # (change requires restart)
-#if_up_cmd = '/usr/bin/sudo /sbin/ip addr add \$_IP_\$/24 dev eth0 label eth0:0'
+if_up_cmd = '/usr/bin/sudo /sbin/ip addr add \$_IP_\$/24 dev ${IF_NAME} label ${IF_NAME}:0'
                                     # startup delegate IP command
                                     # (change requires restart)
-#if_down_cmd = '/usr/bin/sudo /sbin/ip addr del \$_IP_\$/24 dev eth0'
+if_down_cmd = '/usr/bin/sudo /sbin/ip addr del \$_IP_\$/24 dev ${IF_NAME}'
                                     # shutdown delegate IP command
                                     # (change requires restart)
 #arping_path = '/usr/sbin'
                                     # arping command path
                                     # If arping_cmd starts with "/", if_cmd_path will be ignored.
                                     # (change requires restart)
-#arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U \$_IP_\$ -w 1 -I eth0'
+arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U \$_IP_\$ -w 1 -I ${IF_NAME}'
                                     # arping command
                                     # (change requires restart)
 
@@ -780,7 +780,7 @@
                                     # This should be off if client connects to pgpool
                                     # not using virtual IP.
                                     # (change requires restart)
-#wd_escalation_command = ''
+wd_escalation_command = '/etc/pgpool-II/escalation.sh'
                                     # Executes this command at escalation on new active pgpool.
                                     # (change requires restart)
 #wd_de_escalation_command = ''
EOF
#
# また、バックエンド情報を前述のke2-swarm1、ke2-swarm2 及びke2-swarm3
# の設定に従って設定しておきます。 複数バックエンドノードを定義する場
# 合、以下のbackend_*などのパラメータ名の 末尾にノードIDを表す数字を付
# 加することで複数のバックエンドを指定することができます
#
echo '# - Backend Connection Settings for KE2 -' >> ${PGPOOL_CONF_FILE}
i=0
for host in ${CLUSTER_HOSTS}; do
    cat >> ${PGPOOL_CONF_FILE} <<EOF
# - Backend Connection Settings for ${host} -
backend_hostname${i} = '${host}'
backend_port${i} = 5432
backend_weight${i} = 1
backend_data_directory${i} = '/var/lib/pgsql/16/data'
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

#
# サンプルスクリプトfailover.sh及び follow_primary.shは
# /etc/pgpool-II/sample_scripts配下にインストールされていますので、こ
# れらのファイルをコピーして作成します。
#
cp -p /etc/pgpool-II/sample_scripts/failover.sh.sample /etc/pgpool-II/failover.sh
cp -p /etc/pgpool-II/sample_scripts/follow_primary.sh.sample /etc/pgpool-II/follow_primary.sh
cp -p /etc/pgpool-II/sample_scripts/escalation.sh.sample /etc/pgpool-II/escalation.sh
chown postgres:postgres /etc/pgpool-II/{failover.sh,follow_primary.sh,escalation.sh}
#
# escalation.sh の サーバのホスト名、仮想IP、仮想IPを設定するネットワークインターフェースを修正する
#
ed /etc/pgpool-II/escalation.sh <<EOF
,s/^PGPOOLS=.*/PGPOOLS=(${CLUSTER_HOSTS})/
,s/^VIP=.*/VIP=${CLUSTER_VIP}/
,s/^DEVICE=.*/DEVICE=${IF_NAME}/
w
q
EOF

#
# 前述のfollow_primary.shのスクリプトでパスワード入力なしでPCPコマンド
# を実行できるように、すべてのサーバでPgpool-IIの起動ユーザのホームディ
# レクトリに.pcppassを作成します。
#
# su - postgres
su - postgres -c "echo 'localhost:9898:${PG_POOL_USER}:${PG_POOL_PASS}' > ~/.pcppass && chmod 600 ~/.pcppass"

if ${IS_PRIMARY_MODE}; then
    #
    # オンラインリカバリ用のサンプルスクリプトrecovery_1st_stage 及び
    # pgpool_remote_startは /etc/pgpool-II/sample_scripts配下にインストー
    # ルされていますので、 これらのファイルをプライマリサーバ(ke2-swarm1)
    # のデータベースクラスタ配下に配置します。
    #
    su - postgres -c 'cp -p /etc/pgpool-II/sample_scripts/recovery_1st_stage.sample ${PGDATA}/recovery_1st_stage'
    su - postgres -c 'cp -p /etc/pgpool-II/sample_scripts/pgpool_remote_start.sample ${PGDATA}/pgpool_remote_start'
    #
    # オンラインリカバリ機能を使用するには、pgpool_recovery、
    # pgpool_remote_start、pgpool_switch_xlogという関数が必要になるので、
    # ke2-swarm1のtemplate1にpgpool_recoveryをインストールしておきます。
    #
    su - postgres -c 'psql template1 -c "CREATE EXTENSION pgpool_recovery"'
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
cat >> /etc/pgpool-II/pool_hba.conf <<'EOF'
host    all         pgpool           samenet          scram-sha-256
host    all         postgres         samenet          scram-sha-256
host    kompira     kompira          samenet          scram-sha-256
EOF

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
TMP_POOL_USERS_FILE=/tmp/pool_users.txt
cat > ${TMP_POOL_USERS_FILE} <<EOF
${PG_POOL_USER}:${PG_POOL_PASS}
${PG_USER}:${PG_PASS}
${PG_KOMPIRA_USER}:${PG_KOMPIRA_PASS}
EOF
su - postgres -c "pg_enc -m -k ~/.pgpoolkey -i ${TMP_POOL_USERS_FILE}"
rm ${TMP_POOL_USERS_FILE}

#
# すべてのサーバでログファイルを格納するディレクトリを作成します。
# (インストールした時点で作成されているかもしれない)
#
mkdir -p /var/log/pgpool_log
chown postgres:postgres /var/log/pgpool_log
