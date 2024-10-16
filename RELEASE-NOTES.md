# ke2-docker リリースノート

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
