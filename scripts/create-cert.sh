#! /bin/bash
#
# SSL 証明書生成スクリプト
#
# docker コンテナに含まれる openssl コマンドを利用して SSL 証明書を生成します
# デフォルトでは rabbitmq コンテナに含まれる openssl コマンドを利用します
#
# CA証明書/秘密鍵: ca.crt, ca.key
# SSL証明書/秘密鍵: server.crt, server.key
#
# SSL証明書には SAN (subjectAltName) 拡張情報を付与します
#
set -eu
BASE_DIR=$(dirname $(dirname $(readlink -f $0)))

# CA 証明書パラメータ
: ${CA_NAME:=local-ca}
: ${CA_SUBJECT:="/CN=Kompira local CA ($(hostname -s))"}
: ${CA_DAYS:=3650}
: ${CA_KEYTYPE:="rsa:2048"}

# SSL 証明書パラメータ
: ${CERT_NAME:="server"}
: ${CERT_CN:="$(hostname)"}
: ${CERT_SAN_ALTNAMES:="DNS:${CERT_CN}"}
: ${CERT_SUBJECT:="/CN=${CERT_CN}"}
: ${CERT_SAN:="subjectAltName = ${CERT_SAN_ALTNAMES}"}
: ${CERT_DAYS:=3650}
: ${CERT_KEYTYPE:="rsa:2048"}

# docker run パラメータ
: ${LOCAL_UID:=$(id -u)}
: ${LOCAL_GID:=$(id -g)}
: ${SOURCE:=$BASE_DIR/ssl}
: ${TARGET:=/kompira-ssl}

# openssl コマンドを実行できるコンテナイメージ (rabbitmq) の確認
: ${IMAGE:=$(docker images --format="{{.ID}}:{{.Repository}}" | grep -w rabbitmq | head -1 | cut -d: -f1)}
if [ -z "$IMAGE" ]; then
    IMAGE=$(grep "image:" $BASE_DIR/ke2/services/rabbitmq_ssl.yml | sed -re 's/\s*image: //')
    echo "Pull docker image: $IMAGE"
    docker pull "$IMAGE"
    IMAGE=$(docker images --format="{{.ID}}:{{.Repository}}" | grep -w rabbitmq | head -1 | cut -d: -f1)
    if [ -z "$IMAGE" ]; then
        echo "ERROR: docker image not found"
        exit 1
    fi
fi
# openssl コマンドの存在確認
OPENSSL_VERSION=$(docker run -u $LOCAL_UID:$LOCAL_GID $IMAGE openssl version 2>/dev/null || true)
if [ -z "$OPENSSL_VERSION" ]; then
    echo "ERROR: openssl not found in docker image '$IMAGE'"
    exit 1
fi
# 証明書ディレクトリの作成
if [ ! -d $SOURCE ]; then
    mkdir $SOURCE
fi
# CA 証明書の作成
if [ ! -f $SOURCE/$CA_NAME.crt ]; then
    echo "Create local CA certificate: $SOURCE/$CA_NAME.crt"
    docker run -u $LOCAL_UID:$LOCAL_GID -v $SOURCE:$TARGET $IMAGE openssl req -x509 -noenc -newkey $CA_KEYTYPE -days $CA_DAYS -out $TARGET/$CA_NAME.crt -keyout $TARGET/$CA_NAME.key -subj "$CA_SUBJECT"
fi
# SSL 証明書の作成
if [ ! -f $SOURCE/$CERT_NAME.crt ]; then
    echo "Create SSL (self-signed) certificate: $SOURCE/$CERT_NAME.crt"
    docker run -u $LOCAL_UID:$LOCAL_GID -v $SOURCE:$TARGET $IMAGE openssl req -new -newkey $CERT_KEYTYPE -noenc -sha256 -out $TARGET/$CERT_NAME.csr -keyout $TARGET/$CERT_NAME.key -subj "$CERT_SUBJECT"
    echo "$CERT_SAN" > $SOURCE/$CERT_NAME.ext
    docker run -u $LOCAL_UID:$LOCAL_GID -v $SOURCE:$TARGET $IMAGE openssl x509 -req -days $CERT_DAYS -in $TARGET/$CERT_NAME.csr -out $TARGET/$CERT_NAME.crt -CA $TARGET/$CA_NAME.crt -CAkey $TARGET/$CA_NAME.key -CAcreateserial -extfile $TARGET/$CERT_NAME.ext
else
    echo "WARNING: SSL certificate $SOURCE/$CERT_NAME.crt already exists"
fi
