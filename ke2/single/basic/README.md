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
| `POSTGRES_MAX_CONNECTIONS` | PostgreSQL の最大同時接続数（既定 100）。Web の同時処理数（uWSGI の processes×threads）を増やす場合は連動して引き上げてください |
| `POSTGRES_SHARED_BUFFERS` | PostgreSQL の共有バッファサイズ（既定 128MB）                                          |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | プランナのキャッシュサイズ見積り（既定 4GB）                                     |
| `POSTGRES_WORK_MEM` | クエリ毎のソート/ハッシュ作業メモリ（既定 4MB）                                            |
| `POSTGRES_MAINTENANCE_WORK_MEM` | VACUUM・インデックス作成の作業メモリ（既定 64MB）                                |
| `UWSGI_PROCESSES`  | Web サーバ(uWSGI)のワーカプロセス数（既定 5、目安は CPU コア数）                             |
| `UWSGI_THREADS`    | ワーカ1プロセスあたりのスレッド数（既定 1）。同時処理数 = processes×threads。`.wait` / `.recv` 多用時に増やす |
| `UWSGI_LISTEN`     | uWSGI の listen バックログ（既定 100）                                                       |
| `UWSGI_HARAKIRI`   | uWSGI のリクエストタイムアウト秒（既定 0=無効）                                              |
| `UWSGI_THUNDER_LOCK` | スレッド併用時の accept 公平化（既定 false。threads を増やす場合は true 推奨）             |
| `KOMPIRA_NGINX_UWSGI_READ_TIMEOUT` | nginx→uWSGI の read タイムアウト秒（既定 300）。.wait/.recv を長め timeout で使う場合は連動して延ばす |
| `KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT` | nginx→uWSGI の send タイムアウト秒（既定 300） |

なお、同時処理数（`UWSGI_PROCESSES`×`UWSGI_THREADS`）を増やす場合は、同時 DB 接続が
増えるため `POSTGRES_MAX_CONNECTIONS` も連動して引き上げてください
（目安: `processes×threads + 余裕(~15) <= max_connections`）。

カスタマイズ例: 

    $ KOMPIRA_LOG_DIR=/var/log/kompira docker compose up -d
    $ POSTGRES_MAX_CONNECTIONS=200 POSTGRES_SHARED_BUFFERS=512MB docker compose up -d
    $ UWSGI_PROCESSES=8 UWSGI_THREADS=8 UWSGI_THUNDER_LOCK=true POSTGRES_MAX_CONNECTIONS=200 docker compose up -d

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
