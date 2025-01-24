# ke2-docker リリースノート

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
