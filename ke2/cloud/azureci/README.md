# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

このディレクトリには Azure Container Instances (ACI) にデプロイするための Docker Compose ファイルが含まれています。

## 事前準備

作業用の Windows PC を用いて、デプロイ作業を行います。
作業用 PC には、事前に以下の準備が必要です。

1. Azure CLI のインストール
   以下のリンクを参考に作業用の Windows PC に Azure CLI をインストールします。

   https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli

2. ke-docker リポジトリのファイル一式を取得
   https://github.com/fixpoint/ke2-docker から、Code -> Download ZIP を選択し、
   ke-docker リポジトリのファイル一式を取得して、作業用 PC の適当なディレクトリに
   展開します。

## デプロイ手順

### Azure上に各種リソース作成

Azure 上に以下に示すの各種リソースを作成していきます。
(作成するリソースの名前は適宜変更してください)

- リソースグループ: KE20RG
- ストレージアカウント: ke20storage
- PostgreSQLサーバ: postgresql-for-ke

#### Azure へのログインとサブスクリプションの切り替え

以降の作業のために、Azure に CLI からログインして、サブスクリプションを必要に応じて切り替えます。
(Azure CLI は PowerShell 上から実行することを想定しています)

以下のコマンドで Azure にログインします。

```
az login
```
ブラウザが起動するので、画面上からログインしてください。

複数のサブスクリプションが存在する場合、必要に応じて、使用するサブスクリプションを切り替えます。

そのために、アカウントのサブスクリプションの一覧を確認します。
```
az account show
```
以下のコマンドで、必要に応じてサブスクリプションを切り替えることができます。
```
az account set --subscription "<サブスクリプション名>"
```

#### リソースグループとストレージアカウントの作成

リソースグループ作成します。
```
az group create --name KE20RG --location japaneast
```

ストレージアカウントを作成します。
```
az storage account create --name ke20storage --resource-group KE20RG
```

#### Azure Database for PostgreSQL (フレキシブルサーバ) の作成

Azure ポータルにログインして、Azure Database for PostgreSQL (フレキシブルサーバ)リソースを
以下のパラメータで作成します。

- リソースグループ: KE20RG
- サーバ名: postgresql-for-ke
- リージョン: Japan East
- PostgreSQLバージョン: 15
- ワークロードの種類: 必要に応じて適切なプランを選択してください
- 管理ユーザ: kompira
- パスワード: 適切なパスワードを指定してください

作成時に、「Azure 内の任意の Azure サービスにこのサーバーへのパブリック アクセスを許可する」を
チェックしておきます。
他のパラメータはデフォルトでかまいません。

■ PGCRYPTO の有効化
作成した Azure Database for PostgreSQL (フレキシブルサーバ) リソースのサーバパラメタの設定で、
azure.extensions からPGCRYPTO の拡張を有効にしておきます。

■ kompira データベースの作成
PostgreSQL サーバ上に kompira という名称でデータベースを作成しておきます。

#### 共有ファイルボリュームの作成する

Azure Container Instances で必要となる共有ファイルボリュームを以下の名称で作成しておきます。

- kompira-var: /var/opt/kompira のマウント用
- kompira-nginx-conf: nginx の conf ファイル用

※ ファイル共有名に使用できるのは、小文字、数字、ハイフンのみです。
   ファイル共有名の先頭と末尾にはアルファベットまたは数字を使用する必要があります。
   2 つの連続するハイフンを含めることはできません。  

以下のコマンドを実行します。

```
az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name kompira-var


az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name kompira-nginx-conf
```
#### Nginx の conf ファイルのアップロード

Nginx の conf ファイルを kompira-nginx-conf ボリュームに default.conf という名称でアップロードします。

Azure CLI の以下のコマンドで ke-docker に含まれる Nginx の conf ファイルをアップロードします。

```
cd .\ke-docker
az storage file upload --account-name ke20storage -s kompira-nginx-conf --source ./configs/nginx-azure.conf -p default.conf
```

Azure ポータルにログインして、ke20storage ストレージアカウントのファイル共有 kompira-nginx-conf に移動し、
画面上からアップロードすることも可能です。

### アプリケーションを ACI にデプロイ

ke-docker/azureci ディレクトリ上で Azure CLI を使用して ARM テンプレート aci-deployment.json をデプロイします。

以下の環境変数を設定しておく必要があります。

- DATABASE_URL: postgresql への接続URLを指定します
- STORAGE_ACCOUNT_NAME: Azureのストレージアカウント名を指定します
- STORAGE_ACCOUNT_KEY: Azureのストレージアカウントキーを指定します

#### ストレージアカウントキーの取得

ストレージアカウントキーは以下のコマンドを使用して取得できます。

```
az storage account keys list --resource-group KE20RG --account-name ke20storage --output table
```

#### 環境変数の設定
PowerShell上で、以下のコマンドを実行します。

```
$Env:DATABASE_URL = "pgsql://<PostgreSQLユーザ名>:<PostgreSQLユーザのパスワード>@postgresql-for-ke.postgres.database.azure.com:5432/kompira"
$Env:STORAGE_ACCOUNT_NAME = "ke20storage"
$Env:STORAGE_ACCOUNT_KEY = "<取得したストレージアカウントキー>"
```

#### システムの起動

ke-docker/azureci ディレクトリ上で Azure CLI を使用して ARM テンプレートのデプロイ。
```
> cd .\ke-docker\azureci\
> az deployment group create \
  --resource-group KE20RG \
  --template-file aci-deployment.json \
  --parameters databaseUrl=$Env:DATABASE_URL storageAccountName=$Env:STORAGE_ACCOUNT_NAME storageAccountKey=$Env:STORAGE_ACCOUNT_KEY

```

Azure ポータルの KE20RG リソースグループの配下に、azureci コンテナインスタンスが作成されるので、
そこから、各コンテナの状態を確認することができます。
azureci コンテナインスタンスの Public IP アドレス、または keapp.azurecontainer.io にブラウザから HTTP アクセスすると、Kompira Enterprise のログイン画面が表示されるので、ログインすることができます。

#### コンテナログの確認

特定のコンテナのログを確認するには、以下のコマンドを実行します。

■ コンテナ名
- kompira
- kengine
- jobmngrd
- redis
- rabbitmq
- nginx


```
az container logs --resource-group KE20RG --name azureci --container-name <コンテナ名>
```

#### コンテナへのシェルアクセス

特定のコンテナにシェルアクセスするには、以下のコマンドを実行します。

```
az container exec --resource-group KE20RG --name azureci --container-name <コンテナ名> --exec-command /bin/sh
```

#### システムの削除・停止

以下でコンテナを削除します。
```
az deployment group delete --resource-group KE20RG --name azureci
```

コンテナを削除ではなく停止したい場合は、以下のコマンドを実行してコンテナを停止できます。

```
az container stop --resource-group KE20RG --name azureci
```
