# 環境変数

デプロイ時に環境変数を設定しておくことで、Kompira の動作環境を指定することが出来ます。
以下では各構成で共通的な環境変数について示します。
各構成で独自の環境変数が定義されている場合もありますので、それぞれの説明を参照してください。

> **デフォルト値の位置付け**: 以下の表に示す `DATABASE_URL` / `AMQP_URL` / `CACHE_URL` 等のデフォルト値は **kompira コンテナイメージ自体のデフォルト値** であり、docker compose を経由せずコンテナを直接動かす場合などに参照されるものです。**ke2-docker の compose ファイルでは別途上書きされており**、内部 postgres / rabbitmq / redis コンテナへの接続情報 (`DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME` / `AMQP_USER` / `AMQP_PASSWORD` から組み立てた URL、または利用者が指定した `DATABASE_URL` / `AMQP_URL`) が実際の接続先として使われます。

| 環境変数名            | デフォルト                                          | 意味                       |
|-----------------------|-----------------------------------------------------|----------------------------|
| `HOSTNAME`            | (下記参照)                                          | ホスト名                   |
| `KOMPIRA_IMAGE_NAME`  | "kompira.azurecr.io/kompira-enterprise"             | Kompira イメージ           |
| `KOMPIRA_IMAGE_TAG`   | (下記参照)                                          | Kompira タグ               |
| `DATABASE_URL`        | "pgsql://kompira@//var/run/postgresql/kompira"      | データベースの接続先       |
| `DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME` | (下記参照)                | DATABASE_URL の組み立て要素 |
| `AMQP_URL`            | "amqp://guest:guest@localhost:5672"                 | メッセージキューの接続先   |
| `AMQP_USER` / `AMQP_PASSWORD` | (下記参照)                                  | AMQP_URL の組み立て要素     |
| `CACHE_URL`           | "redis://localhost:6379"                            | キャッシュの接続先         |
| `TZ`                  | "Asia/Tokyo"                                        | タイムゾーン               |
| `LANGUAGE_CODE`       | "ja"                                                | 言語設定                   |
| `MAX_EXECUTOR_NUM`    | "0"                                                 | Executor の最大数          |
| `KOMPIRA_LOG_DIR`     | (下記参照)                                          | ログ出力先ディレクトリ     |
| `LOGGING_XXX`         | (下記参照)                                          | プロセスログの設定         |
| `AUDIT_LOGGING_XXX`   | (下記参照)                                          | 監査ログの設定             |
| `UWSGI_XXX`           | (下記参照)                                          | uWSGI の並列度・タイムアウト |
| `KOMPIRA_NGINX_UWSGI_READ_TIMEOUT` | "300"                                  | nginx→uWSGI の read タイムアウト (秒) |
| `KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT` | "300"                                  | nginx→uWSGI の send タイムアウト (秒) |
| `POSTGRES_XXX`        | (下記参照)                                          | PostgreSQL のチューニング  |

## HOSTNAME

デプロイする各コンテナには、ホストサーバのホスト名をベースにしたホスト名を内部的に付与するようにしています。
そのため、デプロイ時にホストサーバのホスト名を環境変数 `HOSTNAME` で参照しています。

環境変数 `HOSTNAME` でホストサーバのホスト名を参照できない環境の場合は、デプロイ前に環境変数 `HOSTNAME` を設定するようにしてください。

## KOMPIRA_IMAGE_NAME / KOMPIRA_IMAGE_TAG

デプロイする Kompira コンテナのイメージとタグを指定します。
独自に用意したコンテナイメージや、特定のバージョンのコンテナイメージを利用したい場合にこの環境変数で指定することができます。

KOMPIRA_IMAGE_TAG のデフォルト値は ke2-docker 更新時点で公開されていた最新の kompira コンテナイメージを示しています（例えば "2.0.2" など）。KOMPIRA_IMAGE_TAG に "latest" と指定すると、デプロイ時に公開されている最新の kompira コンテナイメージを利用することができます。

## DATABASE_URL / AMQP_URL / CACHE_URL

Kompira に必要なサブシステムである、データベースやメッセージキューおよびキャッシュへの接続先を URL 形式で指定します。
デフォルト値ではそれぞれ以下のように接続します。

- データベース: 同じサーバ上の PostgreSQL に Unix ドメインソケットで接続します。
- メッセージキュー: 同じサーバ上の RabbitMQ に TCP 接続します。
- キャッシュ: 同じサーバ上の Redis に TCP 接続します。

参考: https://django-environ.readthedocs.io/en/latest/types.html#environ-env-db-url

なお ke2-docker の compose ファイルでは、`DATABASE_URL` / `AMQP_URL` を直接指定しなかった場合、後述の `DATABASE_USER` 等の個別変数から URL を自動構築する仕組みになっています。

## DATABASE_USER / DATABASE_PASSWORD / DATABASE_NAME / AMQP_USER / AMQP_PASSWORD

接続情報を URL 文字列として `DATABASE_URL` / `AMQP_URL` で指定する代わりに、ユーザ名・パスワード・データベース名を個別の環境変数で指定できます。

| 環境変数名            | デフォルト  | 用途                                                                    |
|-----------------------|-------------|-------------------------------------------------------------------------|
| `DATABASE_USER`       | "kompira"   | DATABASE_URL のユーザ名。single/basic では postgres コンテナの初期ユーザ名にも適用 |
| `DATABASE_PASSWORD`   | "kompira"   | DATABASE_URL のパスワード。single/basic では postgres コンテナの初期パスワードにも適用 |
| `DATABASE_NAME`       | "kompira"   | DATABASE_URL のデータベース名。single/basic では postgres コンテナの初期 DB 名にも適用 |
| `AMQP_USER`           | "guest"     | AMQP_URL のユーザ名。rabbitmq コンテナの初期ユーザ名にも適用            |
| `AMQP_PASSWORD`       | "guest"     | AMQP_URL のパスワード。rabbitmq コンテナの初期パスワードにも適用        |

これらのデフォルト値は互換性のための仮の値です。本番運用前に必ず変更してください。

> **コンテナ初期化への適用は初回起動時のみ**: `DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME` の postgres コンテナへの適用 (`POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`)、および `AMQP_USER` / `AMQP_PASSWORD` の rabbitmq コンテナへの適用 (`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS`) は、それぞれデータボリュームが空の **初回起動時のみ** 行われます。既存のデータボリュームを残したまま値を変更しても、DB 内のユーザ・パスワード・データベース名は更新されません。後から変更する手順は管理者マニュアル「資格情報管理」章を参照してください。

`DATABASE_URL` または `AMQP_URL` を直接指定した場合、**アプリケーション側 (kompira / kengine / jobmngrd) の接続先** には指定された URL がそのまま使われ、対応する個別変数 (`DATABASE_USER` 等または `AMQP_USER` 等) は **接続先 URL の組み立てには使われなくなります**。一方、single/basic 構成における **postgres / rabbitmq コンテナの初期化** には個別変数の値が引き続き使われます (上記「コンテナ初期化への適用は初回起動時のみ」参照)。アプリ側と内部コンテナ側で別の値になると認証不整合が起きるため、`DATABASE_URL` / `AMQP_URL` を独自に指定する場合は個別変数も対応する値に揃えるか、または `DATABASE_URL` / `AMQP_URL` 側を内部コンテナの初期値と一致させてください。

### URL 安全でない文字を含む資格情報の扱い

`DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME` および `AMQP_USER` / `AMQP_PASSWORD` のいずれかに URL 安全でない文字 (RFC 3986 unreserved set 以外。`@` `:` `/` `%` 等の予約文字や空白などを含む) を含む値を設定する場合、組み立てられた URL に正しく埋め込めない問題が発生します。本節はパスワードに限らず、ユーザ名・DB 名にも適用されます (`DATABASE_URL` / `AMQP_URL` を直接指定する場合は、利用者があらかじめパーセントエンコードして埋め込む必要があります)。

URL に文字列を埋め込む際のエンコード規約は [RFC 3986 (URI: Generic Syntax)](https://datatracker.ietf.org/doc/html/rfc3986) で定められています。`DATABASE_URL` / `AMQP_URL` の userinfo (ユーザ名・パスワード部分) や path (DB 名部分) で **URL の区切り文字として解釈される文字** (主に `@` `:` `/` `?` `#` `%` や空白等) を **データの一部として** 埋め込む場合は、`%XX` (XX は ASCII コードの 16 進数表記) でパーセントエンコードする必要があります。安全側に倒すなら、RFC 3986 §2.3 で「unreserved」と定義された英数字および `-` `_` `.` `~` 以外の文字をすべてエンコードしておけば確実です。許容される文字とエンコード規則の詳細は [RFC 3986 §3.2.1 (userinfo)](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.1) / [§3.3 (path)](https://datatracker.ietf.org/doc/html/rfc3986#section-3.3) を参照してください。

主要な変換例:

| 文字 | エンコード後 | 文字       | エンコード後 |
|------|--------------|------------|--------------|
| `@`  | `%40`        | `?`        | `%3F`        |
| `:`  | `%3A`        | `#`        | `%23`        |
| `/`  | `%2F`        | `%`        | `%25`        |
| `+`  | `%2B`        | `&`        | `%26`        |
| `=`  | `%3D`        | ` ` (空白) | `%20`        |

実例: 実パスワード `p@ss:w0rd` を `DATABASE_URL` に埋め込む場合は、`pgsql://user:p%40ss%3Aw0rd@host:5432/db` のように `p@ss:w0rd` → `p%40ss%3Aw0rd` に変換して指定します。

各環境変数の挙動:

- **`DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME`**:
    - `DATABASE_URL` を直接指定する場合は、URL 安全でない文字を含む値も、上表に従いパーセントエンコードして URL に埋め込めば利用可能です (受け取り側の django-environ が URL デコードするため、kompira コンテナイメージのバージョン依存もありません)。
    - 一方、これらの個別変数を指定して compose 側に `DATABASE_URL` を組み立てさせる場合は、いずれも URL に未エンコードのまま埋め込まれるため、RFC 3986 unreserved set (英数字と `-_.~`) のみを使用してください。
- **`AMQP_USER` / `AMQP_PASSWORD`**: kompira コンテナイメージが **v2.0.5.post2 以降** である必要があります (AMQP_URL の userinfo を URL デコードする修正が必要なため)。v2.0.5.post1 以前のイメージを利用する場合、`AMQP_USER` / `AMQP_PASSWORD` には RFC 3986 unreserved set (英数字と `-_.~`) のみを使用してください。
    - また DB 系同様、これらの個別変数を指定して compose 側に `AMQP_URL` を組み立てさせる場合も、URL に未エンコードのまま埋め込まれるため、unreserved set のみを使用してください。

URL 安全でない文字を含むユーザ名・パスワード・DB 名を安全に設定する場合は、上表に従って各値をあらかじめパーセントエンコードした上で `DATABASE_URL` / `AMQP_URL` に埋め込んでください。詳細は管理者マニュアル「資格情報管理」章を参照してください。

また、シェルコマンドで値全体をシングルクオートで囲む形式 (`DATABASE_URL='pgsql://...'` / `AMQP_URL='amqps://...'` 等) を使う場合、シェル特殊文字 (`#` / 空白 / `$` / `!` 等) を含む値でも安全にコピペできますが、値自体に `'` (シングルクオート) を含む場合は閉じてしまうため別途エスケープが必要です (`'\''` での逐次切替等)。詳細な対処方法は管理者マニュアル「資格情報管理」§5 を参照してください。

## TZ / LANGUAGE_CODE

各コンテナのタイムゾーンと言語コードを設定します。

- タイムゾーンは、画面やログで表示される時刻のタイムゾーンの指定になります。
- 言語コードは "ja" (日本語) または "en" (英語) が指定できます。この値は、初回起動時にインポートする初期データの言語の指定になります。

## MAX_EXECUTOR_NUM

Kompira エンジン (kengine) 上で動作する Executor プロセスの最大数を、**1 つの kengine あたり**で指定します。未設定または 0 の場合は、その kengine コンテナの CPU コア数に従います。明示的に上限を指定する場合は 1 以上の整数を指定してください。

1 つの kengine が起動する Executor 数は、その kengine の CPU コア数 (本値を指定した場合は CPU コア数と本値の小さい方) までです。さらに、**システム全体で動作する Executor の合計数は、導入されているライセンスで付与される最大 Executor 数に制限されます**。複数の kengine を動作させる構成 (Swarm など) では、各 kengine への割り当ては起動時にシステム全体の残り枠から配分されます。

ジョブフローの並列実行数を増やしてスケールしたい場合は、ライセンスの購入とサーバリソース (CPU コア数・ノード) の増強で対応します。なお各 Executor は PostgreSQL への接続を 1 つ保持するため、Executor 数を増やす構成では接続先 PostgreSQL の最大接続数 (内部 postgres 構成では `POSTGRES_MAX_CONNECTIONS`、外部データベース構成では接続先 DB サーバ側で設定) の見積りにも反映してください。

## KOMPIRA_LOG_DIR

ログを保存する **ホスト側のディレクトリ** を指定します。指定するとコンテナ内の `/var/log/kompira` にバインドマウントされます。未指定の場合は、標準シングル構成・外部DBシングル構成では名前付きボリューム `kompira_log` に、Swarm 構成では共有ディレクトリ (`SHARED_DIR`) 配下の `log` ディレクトリに保存されます。(コンテナ内のログ出力パス自体は下記 `LOGGING_DIR` で指定します。)

## LOGGING_XXX / AUDIT_LOGGING_XXX

Kompira コンテナイメージにおけるプロセスログおよび監査ログの設定について指定します。

| 環境変数名(プロセスログ) | 環境変数名(監査ログ)    | 意味                        |
|--------------------------|-------------------------|-----------------------------|
| LOGGING_LEVEL            | AUDIT_LOGGING_LEVEL     | ログレベル                  |
| LOGGING_DIR              | AUDIT_LOGGING_DIR       | ログ出力ディレクトリ        |
| LOGGING_BACKUP           | AUDIT_LOGGING_BACKUP    | ログバックアップ数          |
| LOGGING_WHEN             | AUDIT_LOGGING_WHEN      | ログローテートタイミング    |
| LOGGING_INTERVAL         | AUDIT_LOGGING_INTERVAL  | ログローテートインターバル  |

- `LOGGING_LEVEL`: プロセスログの記録レベルを指定します。
    - デフォルトは "INFO" です。
- `AUDIT_LOGGING_LEVEL`: 監査ログの記録レベルを指定します。
    - デフォルトは 2 です。
- `LOGGING_DIR` / `AUDIT_LOGGING_DIR`: ログの出力先ディレクトリを指定します。
    - デフォルトは "/var/log/kompira" です。標準的なデプロイ手順ではこのディレクトリはホストの kompira_log ボリュームにマウントされます。
    - デフォルト (`/var/log/kompira`) から変更する場合は、変更先の出力ディレクトリがコンテナから書き込める形で用意されていることを確認してください。
- `LOGGING_BACKUP`: ログローテート時に保存されるバックアップ数を指定します。
    - `LOGGING_BACKUP` のデフォルトは 7 です。
    - `AUDIT_LOGGING_BACKUP` のデフォルトは 365 です。
- `LOGGING_WHEN` / `AUDIT_LOGGING_WHEN`: ログローテートのタイミングを指定します。デフォルトは "MIDNIGHT" です。
- `LOGGING_INTERVAL` / `AUDIT_LOGGING_INTERVAL`: ログローテートのインターバルを指定します。デフォルトは 1 です。

ログのローテーションは `LOGGING_WHEN` および `LOGGING_INTERVAL` の積に基づいて行います。
`LOGGING_WHEN` は `LOGGING_INTERVAL` の単位を指定するために使います。使える値は下表の通りです。大小文字の区別は行いません。

| LOGGING_WHEN の値   | LOGGING_INTERVAL の単位   |
|---------------------|---------------------------|
| "S"                 | 秒                        |
| "M"                 | 分                        |
| "H"                 | 時間                      |
| "D"                 | 日                        |
| "W0"-"W6"           | 曜日 (0=月曜)             |
| "MIDNIGHT"          | 深夜0時                   |

## UWSGI_XXX / KOMPIRA_NGINX_UWSGI_READ_TIMEOUT / KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT

kompira コンテナで動作する uWSGI (アプリケーションサーバ) のワーカ並列度・タイムアウトと、その前段の nginx から uWSGI へのタイムアウトを指定します。いずれも未設定ならデフォルト値で動作するため、通常はそのままで構いません。

| 環境変数名           | デフォルト | 意味                                          |
|----------------------|-----------|-----------------------------------------------|
| `UWSGI_PROCESSES`    | "5"       | uWSGI のワーカプロセス数 (目安は CPU コア数)   |
| `UWSGI_THREADS`      | "1"       | 1 ワーカあたりのスレッド数。同時処理数 = processes × threads |
| `UWSGI_LISTEN`       | "100"     | 接続待ち行列 (listen backlog) の長さ           |
| `UWSGI_HARAKIRI`     | "0"       | リクエスト処理のタイムアウト秒 (0 で無効)      |
| `UWSGI_THUNDER_LOCK` | "false"   | 複数ワーカ/スレッドでの接続受け付けの公平化    |
| `KOMPIRA_NGINX_UWSGI_READ_TIMEOUT` | "300" | nginx→uWSGI の read タイムアウト秒        |
| `KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT` | "300" | nginx→uWSGI の send タイムアウト秒        |

以下のような場合に、環境変数の調整で改善できることがあります。

- 高負荷でアクセスが全体的に遅い／同時処理数を上げたい → `UWSGI_PROCESSES` / `UWSGI_THREADS` / `UWSGI_THUNDER_LOCK`（あわせて `POSTGRES_MAX_CONNECTIONS` も連動）
- 時間のかかる処理（大きなエクスポート・重いクエリなど）が完了前にタイムアウトで打ち切られてしまう → `KOMPIRA_NGINX_UWSGI_READ_TIMEOUT` / `KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT`
- 想定を超えて長時間実行され続けるリクエストがワーカを占有し続けるのを、一定時間で強制的に打ち切りたい → `UWSGI_HARAKIRI`
- 短時間に接続が集中して、接続が拒否される・つながりにくくなる → `UWSGI_LISTEN`
- 大規模データ環境で、搭載メモリに合わせて PostgreSQL を追加調整したい → `POSTGRES_SHARED_BUFFERS` / `POSTGRES_EFFECTIVE_CACHE_SIZE` / `POSTGRES_WORK_MEM` など (下記 POSTGRES_XXX 参照)

並列度 (`UWSGI_PROCESSES` × `UWSGI_THREADS`) を上げる場合は、同時 DB 接続数も増えるため `POSTGRES_MAX_CONNECTIONS` (下記参照) も連動して引き上げてください。不足すると "FATAL: sorry, too many clients already" で接続が拒否されます。(外部データベース構成では `POSTGRES_MAX_CONNECTIONS` は無効で、接続先 DB サーバの `max_connections` を調整します。)

調整の考え方や設定値の見積りの詳細は、管理者マニュアル「環境変数」章を参照してください。

## POSTGRES_XXX

内部 postgres コンテナを持つ構成 (標準シングル構成) で、PostgreSQL の主要なチューニング項目を指定します。外部データベース構成 (single/extdb・cluster/swarm) では内部 postgres を起動しないため対象外で、チューニングは接続先の外部 DB サーバ側で行います。いずれも未設定なら PostgreSQL の標準値で動作します。

| 環境変数名                      | デフォルト | 対応する postgres 設定      |
|---------------------------------|-----------|-----------------------------|
| `POSTGRES_MAX_CONNECTIONS`      | "100"     | `max_connections`           |
| `POSTGRES_SHARED_BUFFERS`       | "128MB"   | `shared_buffers`            |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | "4GB"     | `effective_cache_size`      |
| `POSTGRES_WORK_MEM`             | "4MB"     | `work_mem`                  |
| `POSTGRES_MAINTENANCE_WORK_MEM` | "64MB"    | `maintenance_work_mem`      |

- `POSTGRES_MAX_CONNECTIONS`: 受け付ける最大同時接続数です。上記の Web ワーカ並列度と連動して設定します。
- メモリ関連パラメータ (`POSTGRES_SHARED_BUFFERS` / `POSTGRES_EFFECTIVE_CACHE_SIZE` / `POSTGRES_WORK_MEM` / `POSTGRES_MAINTENANCE_WORK_MEM`) は、ホストの搭載メモリを基準に決めます。

各パラメータの詳細・見積りは、管理者マニュアル「環境変数」章および PostgreSQL のドキュメントを参照してください。
