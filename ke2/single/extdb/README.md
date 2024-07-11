# Kompira Enterprise 2.0: シングル DB 外部構成

このディレクトリにはオンプレ環境でのシングル DB 外部構成用の Docker Compose ファイルが含まれています。

この構成では Kompira Enterprise に必要なミドルウェアのうち、データベース以外を Docker コンテナで動作させます。
データベースについては必要な設定を行なった PostgreSQL をユーザ側で事前に準備していただく必要があります。

## 外部データベースの準備

この構成では、外部データベースとして以下の要件を満たす PostgreSQL が必要になります。

- バージョン: 12 以上
- その他: 拡張モジュール pgcrypto がインストールされていること (RHEL系 であれば、postgresql-contrib パッケージをインストールしておく必要があります)

Docker が動作しているホストサーバ、あるいは別のサーバ上に要件を満たす PostgreSQL を準備してください。

### 接続仕様の準備

この構成では、Docker コンテナで動作するサービスからデータベースに接続するための情報を、環境変数 DATABASE_URL で指定する必要があります。

    DATABASE_URL=pgsql://<ユーザ名>:<パスワード>@<アドレス>:<ポート番号>/<データベース名>

たとえば外部データベースの接続に必要なパラメータが以下のような場合を考えます。

| 設定項目       | パラメータ例    |
| -------------- | --------------- |
| ユーザ名       | kompira         |
| パスワード     | kompira         |
| IPアドレス     | 10.20.0.XXX     |
| ポート番号     | 5432            |
| データベース名 | kompira         |

この場合、環境変数 DATABASE_URL は次のように指定することになります。

    DATABASE_URL=pgsql://kompira:kompira@10.20.0.XXX:5432/kompira

実際に準備した、またはこれから準備する PostgreSQL サーバの構成に合わせて、DATABASE_URL に指定する値を準備しておいてください。

### PostgreSQL の準備

PostgreSQL のインストールについては準備する環境に合わせて、OS のマニュアルなどを参考にして実施してください。

以下では、PostgreSQL の最低限必要になる設定手順について記述しますので、用意した PostgreSQL サーバ上で実施してください。
詳細な設定方法については PostgreSQL のホームページや公式ドキュメントを参照してください。

**(1) kompira ユーザーとデータベースの作成**

ユーザを作成します。ここではデフォルトの "kompira" という名前で作成します。パスワードの設定も求められるのでこれもデフォルトの "kompira" と入力してください。

    $ sudo -i -u postgres createuser -d -P "kompira"

上で作成したユーザをオーナーとするデータベースを作成します。ここではデフォルトの "kompira" という名前で作成します。
    
    $ sudo -i -u postgres createdb --owner="kompira" --encoding=utf8 "kompira"

**(2) PostgreSQL サーバの接続設定**

ローカルホスト以外からも PostgreSQL サーバに接続できるように設定します。
postgresql.conf (RHEL系標準パッケージをインストールした場合は /var/lib/pgsql/data/postgresql.conf) の listen_address を以下のように設定してください。

    listen_address = '*'

**(3) PostgreSQL のクライアント認証の設定**

手順 (1) で作成したユーザからパスワード接続できるように、pg_hba.conf (RHEL系標準パッケージをインストールした場合は /var/lib/pgsql/data/pg_hba.conf) に host 設定を追加してください。
たとえば Docker が動作しているホストが PostgreSQL サーバと同じネットワークに配置している場合は、以下のような行を追加してください。

    host    kompira         kompira         samenet             scram-sha-256

あるいは、Docker が異なるネットワークに配置されている場合は、"samenet" の部分を CIDR 形式などで指定するようにしてください。

    host    kompira         kompira         10.10.0.0/16        scram-sha-256

これらの設定を行なった後は、一度 postgresql サービスを再起動してください。

## Kompira Enterpise の開始

以降の説明はこのディレクトリで作業することを前提としていますので、このディレクトリに移動してください。

    $ cd ke2/single/extdb

まず、コンテナイメージの取得と SSL 証明書の生成を行なうために、以下のコマンドを実行します。

    $ docker compose pull
    $ ../../../scripts/create-cert.sh

次に、データベース上でのパスワード情報などの暗号化に用いる秘密鍵をファイル `.secret_key` に準備します。
Kompira 用データベースを新規に構築する場合は、以下のようにして空のファイルを用意してください。

    $ touch .secret_key

※ 外部データベースとして既に構築されている Kompira データベースを用いる場合は、そのデータベースにおける秘密鍵を `.secret_key` に書き込んでおいてください。

続けて、以下のコマンドを実行して Kompira Enterprise 開始をします。
このとき先に準備した環境変数 DATABASE_URL を指定するようにしてください。

    $ DATABASE_URL=pgsql://... docker compose up -d

## カスタマイズ
### 環境変数によるカスタマイズ

docker compose up するときに環境変数を指定することで、簡易的なカスタマイズを行なうことができます。

    $ 環境変数=値... docker compose up -d

この構成で指定できる環境変数を以下に示します。

| 環境変数           | 備考                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `DATABASE_URL`     | 外部データベース                                                                            |
| `KOMPIRA_LOG_DIR`  | ログファイルの出力先ディレクトリ（未指定の場合は kompira_log ボリューム内に出力されます）   |

カスタマイズ例: 

    $ DATABASE_URL=pgsql://... KOMPIRA_LOG_DIR=/var/log/kompira docker compose up -d

### 詳細なカスタマイズ

コンテナ構成などを詳細にカスタマイズしたい場合は、docker compose ファイルを編集する必要があります。
まずは、カスタマイズ用の docker compose ファイルを作成するために、このディレクトリで以下のコマンドを実行してください。

    $ docker compose config -o docker-compose.custom.yml

なお、このときに環境変数のカスタマイズを指定することもできます。

    $ KOMPIRA_LOG_DIR=/var/log/kompira docker compose config -o docker-compose.custom.yml

docker-compose.custom.yml という YAML ファイルが作成されますので、目的に合わせてカスタマイズしてください。
このファイルを用いてシステムを開始する場合は、以下のコマンドを実行してください。

    $ docker compose -f docker-compose.custom.yml up -d

## システムの管理

より詳しいシステムの管理手順などについては、「KE 2.0 管理マニュアル」を参照してください。
