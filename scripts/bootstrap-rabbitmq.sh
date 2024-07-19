#! /bin/sh
set -e

# SSL 証明書を /etc/rabbitmq/ssl にコピーしてパーミッション変更
/bin/cp -f -a -r -T /run/.kompira_ssl /etc/rabbitmq/ssl
chown -R rabbitmq:rabbitmq /etc/rabbitmq/ssl 

# SSL 認証プラグインを有効化
rabbitmq-plugins enable rabbitmq_auth_mechanism_ssl

# rabbitmq-server を起動
exec rabbitmq-server "$*"
