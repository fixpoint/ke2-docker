#! /bin/bash
#
# SSL 証明書リロードスクリプト
#
# 各 docker コンテナに SSL 証明書をリロードさせます。
# ホスト上で SSL 証明書を更新したときなどに利用します。
#
# SSL証明書/秘密鍵: server.crt, server.key
#
set -eu

# コンテナ名
: ${NGINX:=nginx}
: ${RABBITMQ:=rabbitmq}

# docker exec コマンド
: ${DOCKER_EXEC:="docker exec -it"}

# Nginx コンテナに SSL 証明書をリロードさせる
cid_nginx=$(docker ps -q -f name=$NGINX)
if [ -n "$cid_nginx" ]; then
    echo "Reload SSL certificate in $NGINX container ($cid_nginx)"
    $DOCKER_EXEC $cid_nginx nginx -s reload
fi

# RabbitMQ コンテナに SSL 証明書をリロードさせる
cid_rabbitmq=$(docker ps -q -f name=$RABBITMQ)
if [ -n "$cid_rabbitmq" ]; then
    echo "Reload SSL certificate in $RABBITMQ container ($cid_rabbitmq)"
    $DOCKER_EXEC $cid_rabbitmq sh -c "/bin/cp -f -a -r -T /run/.kompira_ssl /etc/rabbitmq/ssl && chown -R rabbitmq:rabbitmq /etc/rabbitmq/ssl && rabbitmqctl eval 'ssl:clear_pem_cache().'"
fi
