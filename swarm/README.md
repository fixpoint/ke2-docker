# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

このディレクトリにはマルチエンジン Swarm デプロイ構成用の Docker Compose ファイルが含まれています。

Swarm デプロイ構成は、PostgreSQL/Pgpool-II データベース、および、複数ホスト間の共有ファイルシステムをユーザー側で用意し、
それ以外の Kompira Enterprise を動作させるために必要なミドルウェアを Docker Swarm で動作させます。

Docker Swarm、PostgreSQL/Pgpool-II、および、GlusterFS (を用いた共有ファイルシステム) の構築手順については、
別ドキュメントをご参照ください。

## システムの開始

以下のコマンドを実行して Kompira Enterprise 開始します。

```
$ export LOCAL_UID=$UID LOCAL_GID=$(id -g)
$ SHARED_DIR=<共有ディレクトリのパス> VIP=<Pgpool-II の仮想IPアドレス> docker stack deploy -c docker-compose.yml ke2me
```

SHARED_DIR には、共有ファイルシステム上の共有ディレクトリを指定します。
あらかじ、共有ディレクトリには以下のファイルやディレクトリを作成しておく必要があります。

- ${SHARED_DIR}/
    - configs/
        - fluentd.conf          # swarm 用の fluentd.conf を使います
	- kompira_audit.yml
	- kompira.conf
	- nginx-default.conf
    - log/
    - home/    

### システムの停止

Kompira Enterprise を停止するには以下のコマンドを実行します。

```
$ docker stack rm ke2me
```
