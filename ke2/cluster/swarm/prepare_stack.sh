#! /bin/sh

set -eu
: ${LOGGING_MODE:=single}
: ${KOMPIRA_LOG_DIR:=$SHARED_DIR/log}
: ${KOMPIRA_VAR_DIR:=$SHARED_DIR/var}
: ${KOMPIRA_SSL_DIR:=$SHARED_DIR/ssl}
: ${DATABASE_URL:=""}
: ${DATABASE_HOST:="host.docker.internal"}

if [ ! -f "docker-compose.$LOGGING_MODE-logging.yml" ]; then
    echo "ERROR: Invalid LOGGING_MODE ($LOGGING_MODE)" > /dev/stderr
    exit 1
fi
if [ ! -w "$KOMPIRA_LOG_DIR" ]; then
    echo "ERROR: KOMPIRA_LOG_DIR ($KOMPIRA_LOG_DIR) is not writable" > /dev/stderr
    exit 1
fi
if [ ! -w "$KOMPIRA_VAR_DIR" ]; then
    echo "ERROR: KOMPIRA_VAR_DIR ($KOMPIRA_VAR_DIR) is not writable" > /dev/stderr
    exit 1
fi
if [ ! -w "$KOMPIRA_SSL_DIR" ]; then
    echo "ERROR: KOMPIRA_SSL_DIR ($KOMPIRA_SSL_DIR) is not writable" > /dev/stderr
    exit 1
fi
if [ -z "$DATABASE_URL" ]; then
    if [ -z "$DATABASE_HOST" ]; then
        echo "ERROR: DATABASE_URL or DATABASE_HOST is required" > /dev/stderr
        exit 1
    fi
    DATABASE_URL="pgsql://kompira:kompira@$DATABASE_HOST:9999/kompira"
fi

# SSL 証明書を共有ディレクトリにコピーする
/bin/cp -f -a -r -T ../../../ssl $KOMPIRA_SSL_DIR
echo "OK: SSL files have been copied to the shared directory"

# docker stack deploy 用の docker-swarm.yml ファイルを準備する
# MEMO: docker compose config の結果はそのままでは docker stack が扱えない場合がある
# 一部の項目について正規化することで docker stack でも扱えるようにする
export KOMPIRA_LOG_DIR KOMPIRA_VAR_DIR KOMPIRA_SSL_DIR DATABASE_URL
docker compose -f docker-compose.yml -f docker-compose.$LOGGING_MODE-logging.yml config | sed -r -e '/^name:/d' -e 's/"([0-9]+)"/\1/' > docker-swarm.yml
echo "OK: docker-swarm.yml prepared"

# services.rabbitmq.hostname のフォーマットを取得する
rabbitmq_hostname_format=$(cat docker-swarm.yml | sed -nre '/^\s+rabbitmq:/,/^\s+hostname:/p' | sed -nre 's/^\s*hostname:\s*(.*)/\1/p')
if [ -z "$rabbitmq_hostname_format" ]; then
    echo "ERROR: rabbitmq hostname format could not be identified." > /dev/stderr
    exit 1
fi
# rabbitmq-cluster.conf を準備する
(
    index=0
    cat ../../../configs/rabbitmq-cluster.conf
    for hostname in $(docker node ls --format '{{.Hostname}}'); do
        index=$((index+1))
        # MEMO: hostname を services.rabbitmq.hostname の形式に合わせる
        # MEMO: {{.Node.Hostname}} と {{.Task.Slot}} の置換にのみ対応
        rabbitmq_hostname=$(echo ${rabbitmq_hostname_format} | sed -e "s/{{.Node.Hostname}}/$hostname/" -e "s/{{.Task.Slot}}/$index/")
        echo "cluster_formation.classic_config.nodes.$index = rabbit@$rabbitmq_hostname"
    done
    if [ $index == 0 ]; then
        echo "ERROR: Swarm node list could not be retrieved." > /dev/stderr
        exit 1
    fi
) > ./rabbitmq-cluster.conf
echo "OK: rabbitmq-cluster.conf prepared"

# KE2 スタックの準備完了
echo ""
echo "To start the ke2 stack, please execute the following command"
echo "$ docker stack deploy -c docker-swarm.yml ke2"
