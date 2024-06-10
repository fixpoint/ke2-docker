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
: ${LOGIN_USER:=${SUDO_USER}}

SSH_KEYFILE_NAME=id_rsa_pgpool
#
# 自ホストの postgres ユーザーの SSH 公開鍵ファイルをクラスタの他のホストの authorized_keys に追加する
#
for host in ${CLUSTER_HOSTS}; do
   if [[ ${HOST_NAME} == ${host} ]]; then
	continue
   fi
   KEY_DATA=$(cat /var/lib/pgsql/.ssh/${SSH_KEYFILE_NAME}.pub)
   ssh -t ${LOGIN_USER}@${host} sudo -i -u postgres sh -c "'grep -qs ${HOST_NAME} ~/.ssh/authorized_keys || (mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo ${KEY_DATA} >> ~/.ssh/authorized_keys && restorecon -Rv ~/.ssh)'"
done
