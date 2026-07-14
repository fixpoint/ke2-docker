# ke2-docker リリースノート

---
## 2026/07/17 (2.0.5-latest)
### 変更
- 外部のデータベース/RabbitMQ に接続する構成で、その接続先 URL が未指定の場合に、docker compose の起動段階で即座にエラー停止するようにしました。
    - single/extdb・cluster/swarm 構成: 外部のデータベースに接続するため DATABASE_URL の指定が必須
    - extra/jobmngrd 構成: 外部の RabbitMQ に接続するため AMQP_URL の指定が必須
- 各コンテナでのデータベース/RabbitMQ 接続の資格情報を個別の環境変数で指定可能にしました。
    - DATABASE_USER: データベース接続ユーザ名 (既定: kompira)
    - DATABASE_PASSWORD: データベース接続パスワード (既定: kompira)
    - DATABASE_NAME: 接続するデータベース名 (既定: kompira)
    - AMQP_USER: RabbitMQ (AMQP) 接続ユーザ名 (既定: guest)
    - AMQP_PASSWORD: RabbitMQ (AMQP) 接続パスワード (既定: guest)
- postgres コンテナの PostgreSQL チューニング項目を環境変数で調整可能にしました。
    - POSTGRES_MAX_CONNECTIONS: 最大同時接続数 (max_connections) (既定: 100)
    - POSTGRES_SHARED_BUFFERS: 共有バッファサイズ (shared_buffers) (既定: 128MB)
    - POSTGRES_EFFECTIVE_CACHE_SIZE: プランナが想定する OS キャッシュ量 (effective_cache_size) (既定: 4GB)
    - POSTGRES_WORK_MEM: ソート/ハッシュ等の作業メモリ (work_mem) (既定: 4MB)
    - POSTGRES_MAINTENANCE_WORK_MEM: VACUUM 等の保守処理用作業メモリ (maintenance_work_mem) (既定: 64MB)
- kompira コンテナの uWSGI ワーカ並列度・タイムアウト系を環境変数で調整可能にしました。同時処理数を上げる場合は POSTGRES_MAX_CONNECTIONS も連動して引き上げてください。
    - UWSGI_PROCESSES: ワーカプロセス数 (既定: 5)
    - UWSGI_THREADS: ワーカプロセスあたりのスレッド数。同時処理数 = processes × threads (既定: 1)
    - UWSGI_LISTEN: リッスンキュー (backlog) の長さ (既定: 100)
    - UWSGI_HARAKIRI: リクエスト処理のタイムアウト秒。0 で無効 (既定: 0)
    - UWSGI_THUNDER_LOCK: 複数ワーカ/スレッドへの接続を公平に振り分ける。threads を増やす場合は有効化を推奨 (既定: false)
- nginx コンテナの uwsgi read/send タイムアウトを環境変数で調整可能にしました。
    - KOMPIRA_NGINX_UWSGI_READ_TIMEOUT: uwsgi からの応答読み取りタイムアウト秒 (既定: 300)
    - KOMPIRA_NGINX_UWSGI_SEND_TIMEOUT: uwsgi へのリクエスト送信タイムアウト秒 (既定: 300)

### 修正
- cluster/swarm 構成の setup_stack.sh について、エラーになる場合がある問題の修正と堅牢性の改善を行ないました。
    - 共有ディレクトリ (SHARED_DIR) が root など実行ユーザ以外の所有でも SSL 証明書のコピーが失敗しないようにしました。
    - 非対話シェルで HOSTNAME 未設定でも docker-swarm.yml を生成できるようにしました。
    - SHARED_DIR 未指定時や SSL 未生成時には分かりやすいエラーで停止するようにしました。
- create-cert.sh について、コンテナイメージ取得まわりの不具合の修正と堅牢化を行ないました。
    - ローカルに rabbitmq イメージが無い場合に、fallback が存在しないファイルを参照して失敗する不具合を修正しました。
    - コンテナイメージ参照 (image 行) の抽出処理を堅牢化しました。

### その他
- ホスト実行スクリプトについて、互換性および堅牢性の改善を行ないました。
    - create-cert.sh のパス解決や sed / hostname の呼び出しを互換性の高い形に改善しました。
    - reload-cert.sh を非対話 (非 TTY) 実行でも動作するように改善しました。
    - .gitattributes を追加して改行コードを LF に正規化しました。

---
## 2026/03/06 (2.0.5-latest)
### 変更
- create-cert.sh: Python 3.13 および厳格なSSL検証環境に対応しました。(#95)

---
## 2025/12/12 (2.0.5-latest)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.5-latest に更新しました。

---
## 2025/10/10 (2.0.4.post1)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.4.post1 に更新しました。

---
## 2025/08/01 (2.0.4)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.4 に更新しました。

### 追加
- KE2 ACI をサブネット内にデプロイできるようにしました。
- KE2 ACIにおいて、ログ管理のオプションを追加しました。
- SSL証明書リロードスクリプト reload-cert.sh を追加しました。

---
## 2025/04/11 (2.0.3)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.3 に更新しました。

### 変更
- ACI にも ngninx の共通設定を利用できるにしました。
- nginx のディレクティブをグローバル設定に移動しました。

---
## 2025/01/24 (2.0.2.post1)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.2.post1 に更新しました。

### 追加
- nginx の公開ポートモードを環境変数 NGINX_PORT_MODE で設定できるようにしました。
- jobmngrd コンテナに環境変数 DATABASE_URL, CACHE_URL を渡せるようにしました。
- [ACI] 最大エグゼキュータ数 (MAX_EXECUTOR_NUM) をパラメーター変数 (maxExecutor) で指定できるようにしました。

### 変更
- HTTP レスポンスヘッダの Server: にサーバのバージョン情報が載らないようにしました。
- [nginx] client request header size の設定値を 2*32KB に変更しました。
- [uwsgi] request header size の設定値を 64KB に変更しました。
- kompira および kengine コンテナにおいて net.ipv4.tcp_keepalive_time を 1800 に設定しました。

---
## 2024/10/16 (2.0.2)
### コンテナイメージ
- KOMPIRA_IMAGE_TAG を 2.0.2 に更新しました。

### 構成
- 以下の構成に対応しました。
    - ke2/cloud/azureci

### 追加
- ログ設定 (LOGGING_XXX, AUDIT_LOGGING_XXX) を環境変数で指定できるようにしました。
- 最大エグゼキュータ数 (MAX_EXECUTOR_NUM) を環境変数で指定できるようにしました。
- 環境変数 `${KOMPIRA_HOST}`, `${KOMPIRA_PORT}` で nginx の upstream django サーバを指定できるようにしました。

### 変更
- 環境変数 HOSTNAME が指定されていない場合はエラーになるようにしました。
- 環境変数の説明を Environment.md に独立させました。
- rabbimq の cluster_partition_handling 設定を pause_minority に更新しました。
- docker-compose-plugin について v2.24.6 以上が必要であることを追記しました。

---
## 2024/07/18 (2.0.0)
- 初版リリース
- 以下の構成に対応しました。
    - ke2/single/basic
    - ke2/single/extdb
    - ke2/cluster/swarm
- 以下の構成については現状動作確認できておらずサポート対象外です。
    - ke2/cloud/azureci
