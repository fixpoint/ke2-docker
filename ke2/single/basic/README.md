# Kompira Enterprise 2.0: 標準シングル構成

このディレクトリにはオンプレ環境での標準シングル構成（オールインワン）用の Docker Compose ファイルが含まれています。

標準シングル構成は Kompira Enterprise に必要なすべてのミドルウェアを Docker コンテナで動作させるオールインワン構成ため、簡単に始めることができます。

## クイックスタート

以降の説明はこのディレクトリで作業することを前提としていますので、このディレクトリに移動してください。

    $ cd ke2/single/basic

まず、コンテナイメージの取得と SSL 証明書の生成を行なうために、以下のコマンドを実行します。

    $ docker compose pull
    $ ../../../scripts/create-cert.sh

続けて、以下のコマンドを実行して Kompira Enterprise 開始をします。

    $ docker compose up -d

Kompira Enterprise の開始に成功したら、システムが正常に動作しているかを確認してください。
ブラウザで以下のアドレスにアクセスしてください（開始に１分程度かかる場合があります）。

    http://<サーバーのアドレス>/.login

ログイン画面が表示されたら、以下の通り入力して Kompira Enterprise にログインしてください。

- ユーザ名：`root`
- パスワード：`root`

ログインが確認できたら、動作確認は完了です。

## カスタマイズ
### 環境変数によるカスタマイズ

docker compose up するときに環境変数を指定することで、簡易的なカスタマイズを行なうことができます。

    $ 環境変数=値... docker compose up -d

この構成で指定できるカスタマイズ用の環境変数を以下に示します。

| 環境変数           | 備考                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `KOMPIRA_LOG_DIR`  | ログファイルの出力先ディレクトリ（未指定の場合は kompira_log ボリューム内に出力されます）   |

カスタマイズ例: 

    $ KOMPIRA_LOG_DIR=/var/log/kompira docker compose up -d

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
