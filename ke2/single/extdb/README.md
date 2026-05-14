# Kompira Enterprise 2.0: 外部DBシングル構成

このディレクトリにはオンプレ環境での外部DBシングル構成用の Docker Compose ファイルが含まれています。

この構成では Kompira Enterprise に必要なミドルウェアのうち、データベース以外を Docker コンテナで動作させます。
データベースについては必要な設定を行なった PostgreSQL をユーザ側で事前に準備していただく必要があります。

## 外部データベースの準備

この構成では、外部データベースとして以下の要件を満たす PostgreSQL が必要になります。

- バージョン: 12 以上
- その他: 拡張モジュール pgcrypto がインストールされていること (RHEL系 であれば、postgresql-contrib パッケージをインストールしておく必要があります)

Docker が動作しているホストサーバ、あるいは別のサーバ上に要件を満たす PostgreSQL を準備してください。

### 接続仕様の準備

この構成では、Docker コンテナで動作するサービスからデータベースに接続するための情報を、環境変数 DATABASE_URL で指定する必要があります。

    DATABASE_URL=pgsql://<DB ユーザ名>:<DB パスワード>@<DB ホストの IP>:5432/<データベース名>

> **注: 以下のユーザ名・パスワード・データベース名・IP アドレスはあくまで「設定する値の形式」を示す例示です。** 任意の値を使用できますので、お使いの環境のセキュリティポリシーに合わせて設定してください。特にパスワードは推測されにくい十分に強いものを指定してください。

以下では具体的な手順例として、次の値で構成した場合の例を示します。

| 設定項目       | 例示値                                |
| -------------- | ------------------------------------- |
| ユーザ名       | `kompira_user`                        |
| パスワード     | `<十分に強いパスワード>`              |
| IPアドレス     | `10.20.0.10`                          |
| ポート番号     | `5432`                                |
| データベース名 | `kompira_db`                          |

このとき DATABASE_URL は以下のように指定します。

    DATABASE_URL=pgsql://kompira_user:<十分に強いパスワード>@10.20.0.10:5432/kompira_db

実際に準備した、またはこれから準備する PostgreSQL サーバの構成に合わせて、DATABASE_URL に指定する値を準備しておいてください。

> **パスワードに URL 予約文字 (`@` `:` `/` `%` 等) を含める場合**: [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986) に従いパーセントエンコード (`@` → `%40`, `:` → `%3A`, `/` → `%2F` 等) が必要です。詳細な変換規則と例は [Environment.md](../../../Environment.md) 「URL 予約文字を含むパスワードの扱い」または管理者マニュアル「資格情報管理」章を参照。

### PostgreSQL の準備

PostgreSQL のインストールについては準備する環境に合わせて、OS のマニュアルなどを参考にして実施してください。

以下では、PostgreSQL の最低限必要になる設定手順について記述しますので、用意した PostgreSQL サーバ上で実施してください。
詳細な設定方法については PostgreSQL のホームページや公式ドキュメントを参照してください。

**(1) ユーザとデータベースの作成**

ユーザを作成します。ここでは例として "kompira_user" という名前で作成します。パスワードの設定も求められるので、上で準備した値を入力してください。

    $ sudo -i -u postgres createuser -d -P "kompira_user"

上で作成したユーザをオーナーとするデータベースを作成します。ここでは例として "kompira_db" という名前で作成します。

    $ sudo -i -u postgres createdb --owner="kompira_user" --encoding=utf8 "kompira_db"

**(2) PostgreSQL サーバの接続設定**

ローカルホスト以外からも PostgreSQL サーバに接続できるように設定します。
postgresql.conf (RHEL系標準パッケージをインストールした場合は /var/lib/pgsql/data/postgresql.conf) の listen_addresses を以下のように設定してください。

    listen_addresses = '*'

**(3) PostgreSQL のクライアント認証の設定**

手順 (1) で作成したユーザからパスワード接続できるように、pg_hba.conf (RHEL系標準パッケージをインストールした場合は /var/lib/pgsql/data/pg_hba.conf) に host 設定を追加してください。
たとえば Docker が動作しているホストが PostgreSQL サーバと同じネットワークに配置している場合は、以下のような行を追加してください (フィールドは「データベース名 ユーザ名 接続元アドレス 認証方式」)。

    host    kompira_db      kompira_user    samenet             scram-sha-256

あるいは、Docker が異なるネットワークに配置されている場合は、"samenet" の部分を CIDR 形式などで指定するようにしてください。

    host    kompira_db      kompira_user    10.10.0.0/16        scram-sha-256

これらの設定を行なった後は、一度 postgresql サービスを再起動してください。

## Kompira Enterpise の開始

以降の説明はこのディレクトリで作業することを前提としていますので、このディレクトリに移動してください。

    $ cd ke2/single/extdb

まず、コンテナイメージの取得と SSL 証明書の生成を行なうために、以下のコマンドを実行します。

    $ docker compose pull
    $ ../../../scripts/create-cert.sh

次に、データベース上でのパスワード情報などの暗号化に用いる秘密鍵をファイル `.secret_key` に準備します。
Kompira 用データベースを新規に構築する場合は、たとえば以下のようにして空のファイルを用意してください。

    $ touch .secret_key

※ 外部データベースとして既に構築されている Kompira データベースを用いる場合は、そのデータベースにおける秘密鍵を `.secret_key` に書き込んでおいてください。

    $ echo -n 'xxxxxxxxxxxxxxxx' > .secret_key

続けて、以下のコマンドを実行して Kompira Enterprise 開始をします。
このとき先に準備した接続情報を反映した DATABASE_URL を **必ず指定** してください。未指定で起動した場合は `docker compose config` の段階で即エラー停止します。

    $ DATABASE_URL=pgsql://<DB ユーザ名>:<DB パスワード>@<DB ホストの IP>:5432/<データベース名> docker compose up -d

## カスタマイズ
### 環境変数によるカスタマイズ

docker compose up するときに環境変数を指定することで、簡易的なカスタマイズを行なうことができます。

    $ 環境変数=値... docker compose up -d

この構成で指定できる環境変数を以下に示します。

| 環境変数           | 備考                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| `DATABASE_URL`     | 外部データベースの接続 URL。**必須**。未指定の場合は起動時にエラー停止します                      |
| `AMQP_USER`        | 内部 RabbitMQ コンテナのユーザ名（デフォルト: `guest`）                                           |
| `AMQP_PASSWORD`    | 内部 RabbitMQ コンテナのパスワード（デフォルト: `guest`、本番運用前に変更を強く推奨）             |
| `KOMPIRA_LOG_DIR`  | ログファイルの出力先ディレクトリ（未指定の場合は kompira_log ボリューム内に出力されます）         |

カスタマイズ例:

    $ DATABASE_URL=pgsql://... AMQP_PASSWORD='strong-pw' KOMPIRA_LOG_DIR=/var/log/kompira docker compose up -d

> **AMQP_PASSWORD に URL 予約文字 (`@` `:` `/` `%` 等) を含めて利用する場合**: KE2.0 コンテナイメージが **v2.0.5.post2 以降** である必要があります (kompira-v2#367 修正に依存)。v2.0.5.post1 以前のイメージでは `AMQP_PASSWORD` は英数字と `-_.~` のみ使用してください。
>
> 強度の高いパスワードを `.env` で簡単に管理したい場合は、ヘルパースクリプト `../../../scripts/init-env.sh` で `.env` を自動生成できます (任意ステップ)。

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
