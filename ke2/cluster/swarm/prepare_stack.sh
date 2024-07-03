#! /bin/sh

set -eu
: ${LOGGING_MODE:=single}
: ${KOMPIRA_LOG_DIR:=$SHARED_DIR/log}
: ${KOMPIRA_VAR_DIR:=$SHARED_DIR/var}
: ${KOMPIRA_SSL_DIR:=$SHARED_DIR/ssl}
: ${DATABASE_URL:=""}
: ${DATABASE_HOST:="host.docker.internal"}

if [ ! -f "docker-compose.$LOGGING_MODE-logging.yml" ]; then
    echo "ERROR: Invalid LOGGING_MODE ($LOGGING_MODE)"
    exit 1
fi
if [ ! -w "$KOMPIRA_LOG_DIR" ]; then
    echo "ERROR: KOMPIRA_LOG_DIR ($KOMPIRA_LOG_DIR) is not writable"
    exit 1
fi
if [ ! -w "$KOMPIRA_VAR_DIR" ]; then
    echo "ERROR: KOMPIRA_VAR_DIR ($KOMPIRA_VAR_DIR) is not writable"
    exit 1
fi
if [ ! -w "$KOMPIRA_SSL_DIR" ]; then
    echo "ERROR: KOMPIRA_SSL_DIR ($KOMPIRA_SSL_DIR) is not writable"
    exit 1
else
    # SSL 証明書を共有フォルダにコピーする
    /bin/cp -f -a -r -T ../../../ssl $KOMPIRA_SSL_DIR
fi
if [ -z "$DATABASE_URL" ]; then
    if [ -z "$DATABASE_HOST" ]; then
        echo "ERROR: DATABASE_URL or DATABASE_HOST is required"
        exit 1
    fi
    DATABASE_URL="pgsql://kompira:kompira@$DATABASE_HOST:9999/kompira"
fi

export KOMPIRA_LOG_DIR KOMPIRA_VAR_DIR KOMPIRA_SSL_DIR DATABASE_URL
# MEMO: docker compose config の結果はそのままでは docker stack が扱えない場合がある
# 一部の項目について正規化することで docker stack でも扱えるようにする
docker compose -f docker-compose.yml -f docker-compose.$LOGGING_MODE-logging.yml config | sed -r -e '/^name:/d' -e 's/"([0-9]+)"/\1/' > docker-swarm.yml
echo "OK: docker-swarm.yml prepared"
echo "docker stack deploy -c docker-swarm.yml ke2"
