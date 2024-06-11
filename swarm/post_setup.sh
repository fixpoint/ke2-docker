#!/bin/bash
set -eu  # 未定義変数のチェック、コマンドエラー時は処理中断

: ${CLUSTER_HOSTS:?Undefined environment variable. Example: export CLUSTER_HOSTS="'server1 server2 server3'"}
: ${HOST_NAME:=$(hostname)}

#
# root ユーザに切り替える
#
if [[ ${USER} != "root" ]]; then
    echo "root ユーザではありません。sudo 権限で root ユーザに変更します"
    sudo -E su -m -c ${0}
    exit $?
fi
LOGIN_USER=${SUDO_USER:-${USER}}

#
# SSH公開鍵認証の設定
#
# 自動フェイルオーバ、オンラインリカバリ機能を利用するには、すべての
# Pgpool-IIノード間でpostgresユーザ（Pgpool-IIのデフォルトの起動ユーザ。
# Pgpool-II 4.0以前、デフォルトの起動ユーザはroot）として双方向にSSH公
# 開鍵認証（パスワードなし）で接続できるように設定する必要があります。
#
# SSH鍵ファイルを作成します。 この設定例では生成される鍵ファイル名は
# id_rsa_pgpoolとします。(鍵ファイル名を変更する場合、Pgpool-II の各種
# スクリプトも合わせて修正する必要があることに注意してください)
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
# 自ホストの postgres ユーザーの SSH 公開鍵ファイルをクラスタの他のホストの authorized_keys に追加する
#
for host in ${CLUSTER_HOSTS}; do
   if [[ ${HOST_NAME} == ${host} ]]; then
	continue
   fi
   KEY_DATA=$(cat /var/lib/pgsql/.ssh/${SSH_KEYFILE_NAME}.pub)
   ssh -t ${LOGIN_USER}@${host} sudo -i -u postgres sh -c "'sed -i.bak -e /postgres@${HOST_NAME}$/d ~/.ssh/authorized_keys; (mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo ${KEY_DATA} >> ~/.ssh/authorized_keys && restorecon -Rv ~/.ssh)'"
done
