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

# Git Bash / MSYS2 では docker exec に渡す引数中の絶対パス (/bin/cp や /run/... /etc/... 等) が
# Windows パスへ誤変換される。該当環境ではパス変換を無効化する (Linux/macOS/WSL2 では no-op)。
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' ;;
esac

# コンテナ名
: ${NGINX:=nginx}
: ${RABBITMQ:=rabbitmq}

# docker exec コマンド
# 実行するコマンドは非対話 (nginx -s reload / sh -c "...") のため TTY/stdin は不要。
# -t を既定に含めると非 TTY 実行 (CI・スクリプト・パイプ経由) で "the input device is
# not a TTY" になるため既定から外す。対話実行したい場合は DOCKER_EXEC で上書きする。
: ${DOCKER_EXEC:="docker exec"}

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
