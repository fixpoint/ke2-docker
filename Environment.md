# 環境変数

デプロイ時に環境変数を設定しておくことで、Kompira の動作環境を指定することが出来ます。
以下では各構成で共通的な環境変数について示します。
各構成で独自の環境変数が定義されている場合もありますので、それぞれの説明を参照してください。

| 環境変数名            | デフォルト                                          | 意味                       |
|-----------------------|-----------------------------------------------------|----------------------------|
| `HOSTNAME`            | (下記参照)                                          | ホスト名                   |
| `KOMPIRA_IMAGE_NAME`  | "kompira.azurecr.io/kompira-enterprise"             | Kompira イメージ           |
| `KOMPIRA_IMAGE_TAG`   | "latest"                                            | Kompira タグ               |
| `DATABASE_URL`        | "pgsql://kompira@//var/run/postgresql/kompira"      | データベースの接続先       |
| `AMQP_URL`            | "amqp://guest:guest@localhost:5672"                 | メッセージキューの接続先   |
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

## DATABASE_URL / AMQP_URL / CACHE_URL

Kompira に必要なサブシステムである、データベースやメッセージキューおよびキャッシュへの接続先を URL 形式で指定します。
デフォルト値ではそれぞれ以下のように接続します。

- データベース: 同じサーバ上の PostgreSQL に Unix ドメインソケットで接続します。
- メッセージキュー: 同じサーバ上の RabbitMQ に TCP 接続します。
- キャッシュ: 同じサーバ上の Redis に TCP 接続します。

参考: https://django-environ.readthedocs.io/en/latest/types.html#environ-env-db-url

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
