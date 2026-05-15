# 環境変数

デプロイ時に環境変数を設定しておくことで、Kompira の動作環境を指定することが出来ます。
以下では各構成で共通的な環境変数について示します。
各構成で独自の環境変数が定義されている場合もありますので、それぞれの説明を参照してください。

> **デフォルト値の位置付け**: 以下の表に示す `DATABASE_URL` / `AMQP_URL` / `CACHE_URL` 等のデフォルト値は **kompira コンテナイメージ自体の既定値** であり、docker compose を経由せずコンテナを直接動かす場合などに参照されるものです。**ke2-docker の compose ファイルでは別途上書きされており**、内部 `postgres` / `rabbitmq` / `redis` コンテナへの接続情報 (`DATABASE_USER` / `DATABASE_PASSWORD` / `DATABASE_NAME` / `AMQP_USER` / `AMQP_PASSWORD` から組み立てた URL、または利用者が指定した `DATABASE_URL` / `AMQP_URL`) が実際の接続先として使われます。

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
| `LOGGING_XXX`         | (下記参照)                                          | プロセスログの設定         |
| `AUDIT_LOGGING_XXX`   | (下記参照)                                          | 監査ログの設定             |

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
    - `DATABASE_URL` を直接指定するか、`scripts/init-env.sh` で `.env` を生成する場合は、URL 安全でない文字を含む値も利用可能です (受け取り側の django-environ が URL デコードするため、kompira コンテナイメージのバージョン依存もありません)。
    - 一方、これらの個別変数を指定して compose 側に `DATABASE_URL` を組み立てさせる場合は、いずれも URL に未エンコードのまま埋め込まれるため、RFC 3986 unreserved set (英数字と `-_.~`) のみを使用してください。
- **`AMQP_USER` / `AMQP_PASSWORD`**: kompira コンテナイメージが **v2.0.5.post2 以降** である必要があります (AMQP_URL の userinfo を URL デコードする修正が必要なため)。v2.0.5.post1 以前のイメージを利用する場合、`AMQP_USER` / `AMQP_PASSWORD` には RFC 3986 unreserved set (英数字と `-_.~`) のみを使用してください。
    - また DB 系同様、これらの個別変数を指定して compose 側に `AMQP_URL` を組み立てさせる場合も、URL に未エンコードのまま埋め込まれるため、unreserved set のみを使用してください (`scripts/init-env.sh` 経由なら自動でエンコードされます)。

URL 安全でない文字を含むユーザ名・パスワード・DB 名を安全に設定するには、`scripts/url-encode.sh` で個別の文字列をエンコードするか、`scripts/init-env.sh` で `.env` を自動生成する方法を推奨します (init-env.sh は内部で url-encode.sh を利用して URL エンコードを自動処理します)。詳細は管理者マニュアル「資格情報管理」章を参照してください。

また、シェルコマンドで値全体をシングルクオートで囲む形式 (`DATABASE_URL='pgsql://...'` / `AMQP_URL='amqps://...'` 等) を使う場合、シェル特殊文字 (`#` / 空白 / `$` / `!` 等) を含む値でも安全にコピペできますが、値自体に `'` (シングルクオート) を含む場合は閉じてしまうため別途エスケープが必要です (`'\''` での逐次切替、または `scripts/init-env.sh` で `.env` を生成して利用する等)。詳細な対処方法は管理者マニュアル「資格情報管理」§5 を参照してください。

## TZ / LANGUAGE_CODE

各コンテナのタイムゾーンと言語コードを設定します。

- タイムゾーンは、画面やログで表示される時刻のタイムゾーンの指定になります。
- 言語コードは "ja" (日本語) または "en" (英語) が指定できます。この値は、初回起動時にインポートする初期データの言語の指定になります。

## MAX_EXECUTOR_NUM

Kompira エンジン上で動作する Executor プロセスの最大数を指定します。
未設定または 0 を指定した場合は kengine コンテナの CPUコア数だけ Executor プロセスを起動します。
なお、MAX_EXECUTOR_NUM を CPU コア数より多くしても、実行する Executor プロセス数は CPU コア数で抑えられます。

    プロセス数＝min(CPUコア数、MAX_EXECUTOR_NUM)

また、導入されているライセンスによっても実際に動作する Executor のプロセス数は制限されます。

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
