#!/bin/bash

# pipefail: `docker compose config | sed ...` で compose 側の失敗が sed 成功に
# マスクされ、不完全な docker-swarm.yml のまま続行するのを防ぐ (bash 依存)。
set -euo pipefail

# SHARED_DIR は共有ディレクトリのパスとして必須 (以降の KOMPIRA_*_DIR の既定値が参照する)。
# set -u 任せだと汎用的な "unbound variable" になるため、明示的に案内する。
: ${SHARED_DIR:?"環境変数 SHARED_DIR (共有ディレクトリのパス) を指定してください"}

: ${KOMPIRA_LOG_DIR:=$SHARED_DIR/log}
: ${KOMPIRA_VAR_DIR:=$SHARED_DIR/var}
: ${KOMPIRA_SSL_DIR:=$SHARED_DIR/ssl}
: ${DATABASE_URL:=""}
: ${DATABASE_HOST:="host.docker.internal"}
# HOSTNAME はサービス定義 (redis 等の hostname: re-${HOSTNAME}) で参照される。
# 非対話シェル (スクリプト実行や CI 等) では未設定のことがあるため、ここで補完する。
: ${HOSTNAME:=$(hostname)}

if [ ! -w "$KOMPIRA_LOG_DIR" ]; then
    echo "ERROR: KOMPIRA_LOG_DIR ($KOMPIRA_LOG_DIR) is not writable" >&2
    exit 1
fi
if [ ! -w "$KOMPIRA_VAR_DIR" ]; then
    echo "ERROR: KOMPIRA_VAR_DIR ($KOMPIRA_VAR_DIR) is not writable" >&2
    exit 1
fi
if [ ! -w "$KOMPIRA_SSL_DIR" ]; then
    echo "ERROR: KOMPIRA_SSL_DIR ($KOMPIRA_SSL_DIR) is not writable" >&2
    exit 1
fi
if [ -z "$DATABASE_URL" ]; then
    if [ -z "$DATABASE_HOST" ]; then
        echo "ERROR: DATABASE_URL or DATABASE_HOST is required" >&2
        exit 1
    fi
    DATABASE_URL="pgsql://kompira:kompira@$DATABASE_HOST:9999/kompira"
fi

# SSL 証明書を共有ディレクトリにコピーする
# ssl/ に証明書ファイルがあることを確認する。空 (未生成・.gitignore のみ) だと glob `ssl/*` が
# 展開されず、set -e 配下で不明瞭な cp エラーになるため、明示的に案内して停止する。
shopt -s nullglob
_ssl_files=(../../../ssl/*)
shopt -u nullglob
if [ ${#_ssl_files[@]} -eq 0 ]; then
    echo "ERROR: ../../../ssl に証明書がありません。先に scripts/create-cert.sh を実行してください" >&2
    exit 1
fi
# 既定構成の nginx / rabbitmq は server.crt / server.key / local-ca.crt を参照する。
# 既定名が欠けている場合は警告する (create-cert.sh の CERT_NAME/CA_NAME でカスタム名や複数ペアを
# 使う運用もあり得るため、ここでは停止せず警告に留める。その場合は各 SSL 設定側の参照も合わせること)。
for _ssl_file in server.crt server.key local-ca.crt; do
    [ -f "../../../ssl/${_ssl_file}" ] || echo "WARNING: 既定の SSL ファイル ssl/${_ssl_file} が見つかりません (カスタム証明書名の場合は設定側の参照を確認してください)" >&2
done
# -a ではなく --preserve=mode を用いる: SHARED_DIR が別ユーザ所有 (root が作成した共有
# ディレクトリ等) でも、書き込み可能でありさえすれば失敗しないようにする。ディレクトリの
# 時刻・所有者は複製せず (非所有だと -a の時刻保持が EPERM で失敗する)、秘密鍵などの
# ファイルモード (例: server.key の 600) は保持する。
/bin/cp -f -r --preserve=mode -- "${_ssl_files[@]}" "$KOMPIRA_SSL_DIR/"
echo "OK: SSL files have been copied to the shared directory"

# ホスト名がロング形式であるかを判定して環境変数 RABBITMQ_USE_LONGNAME に反映する
export RABBITMQ_USE_LONGNAME=$([ $(hostname) == $(hostname -s) ] && echo 'false' || echo 'true')

# docker stack deploy 用の docker-swarm.yml ファイルを準備する
# MEMO: docker compose config の結果はそのままでは docker stack が扱えない場合がある
# 一部の項目について正規化することで docker stack でも扱えるようにする
export KOMPIRA_LOG_DIR KOMPIRA_VAR_DIR KOMPIRA_SSL_DIR DATABASE_URL HOSTNAME
docker compose config | sed -r -e '/^name:/d' -e 's/"([0-9]+)"/\1/' -e 's/<<(.*)>>/{{\1}}/' > docker-swarm.yml
echo "OK: docker-swarm.yml prepared"

# services.rabbitmq.hostname のフォーマットを取得する
rabbitmq_hostname_format=$(cat docker-swarm.yml | sed -nre '/^\s+rabbitmq:/,/^\s+hostname:/p' | sed -nre 's/^\s*hostname:\s*(.*)/\1/p')
if [ -z "$rabbitmq_hostname_format" ]; then
    echo "ERROR: rabbitmq hostname format could not be identified." >&2
    exit 1
fi
# rabbitmq-cluster.conf を準備する
(
    node_index=0
    cat ../../../configs/rabbitmq-cluster.conf
    for node_hostname in $(docker node ls --format '{{.Hostname}}'); do
        node_index=$((node_index+1))
        # MEMO: node_hostname を services.rabbitmq.hostname の形式に合わせる
        # MEMO: {{.Node.Hostname}} と {{.Task.Slot}} の置換にのみ対応
        rabbitmq_hostname=$(echo ${rabbitmq_hostname_format} | sed -e "s/{{.Node.Hostname}}/$node_hostname/" -e "s/{{.Task.Slot}}/$node_index/")
        echo "cluster_formation.classic_config.nodes.$node_index = rabbit@$rabbitmq_hostname"
    done
    if [ $node_index == 0 ]; then
        echo "ERROR: Swarm node list could not be retrieved." >&2
        exit 1
    fi
) > ./rabbitmq-cluster.conf
echo "OK: rabbitmq-cluster.conf prepared"

# KE2 スタックの準備完了
echo ""
echo "To start the ke2 stack, please execute the following command"
echo "$ docker stack deploy -c docker-swarm.yml ke2"
