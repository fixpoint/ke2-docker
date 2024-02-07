# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

このディレクトリには Azure Container Instances (ACI) にデプロイするための Docker Compose ファイルが含まれています。

## 事前準備

作業用の Windows PC を用いて、デプロイ作業を行います。
作業用 PC には、事前に以下の準備が必要です。

1. Docker Desktop for Windows のインストール
   以下のリンクを参考に作業用の Windows PC に Docker Desktop をインストールします。

   https://docs.docker.jp/docker-for-windows/install.html

2. Azure CLI のインストール
   以下のリンクを参考に作業用の Windows PC に Azure CLI をインストールします。

   https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli

3. ke-docker リポジトリのファイル一式を取得
   https://github.com/fixpoint/ke-docker から、Code -> Download ZIP を選択し、
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


#### Azureコンテクストの作成と切替え

以降の Docker コマンドでの作業のために、Azure コンテクストを作成して、コンテクストを切り替えます。

Docker コマンドで Azure にログインします。
```
docker login azure
```

次にACIコンテクストを作成します。
(ここではコンテクスト名として keacicontext を使用していますが、任意の名前でかまいません)
```
docker context create aci keacicontext --resource-group KE20RG --subscription-id <サブスクリプションID>
```

ACIコンテクストを切り替えます。
```
docker context use keacicontext
```

#### 共有ファイルボリュームの作成する

Docker compose で必要となる共有ファイルボリュームを以下の名称で作成しておきます。

- kompira-var: /var/opt/kompira のマウント用
- kompira-nginx-conf: nginx の conf ファイル用

※ ファイル共有名に使用できるのは、小文字、数字、ハイフンのみです。
   ファイル共有名の先頭と末尾にはアルファベットまたは数字を使用する必要があります。
   2 つの連続するハイフンを含めることはできません。  

以下のコマンドを実行します。

```
docker volume create kompira-var --storage-account ke20storage
docker volume create kompira-nginx-conf --storage-account ke20storage
```
#### Nginx の conf ファイルのアップロード

Nginx の conf ファイルを kompira-nginx-conf ボリュームに default.conf という名称でアップロードします。

Azure CLI の以下のコマンドで ke-docker に含まれる Nginx の conf ファイルをアップロードします。

```
cd .\ke-docker
az storage file upload --account-name ke20storage -s kompira-nginx-conf --source .\configs\nginx-default.conf -p default.conf
```

Azure ポータルにログインして、ke20storage ストレージアカウントのファイル共有 kompira-nginx-conf に移動し、
画面上からアップロードすることも可能です。

### Docker compose 実行

ke-docker からダウンロードしたファイル一式に含まれる ke-docker/azureci/docker-compose.yml を使用して、
Docker compose を実行します。

以下の環境変数を設定しておく必要があります。

- DATABASE_URL: postgresql への接続URLを指定します
- STORAGE_ACCOUNT_NAME: Azureのストレージアカウント名を指定します

PowerShell上で、以下のコマンドを実行します。

```
$Env:DATABASE_URL = "pgsql://<PostgreSQLユーザ名>:<PostgreSQLユーザのパスワード>@postgresql-for-ke.postgres.database.azure.com:5432/kompira"
$Env:STORAGE_ACCOUNT_NAME = "ke20storage"
```

#### システムの起動

ke-docker/azureci ディレクトリ上で docker compose up を実行します。
```
> cd .\ke-docker\azureci\
> docker compose up
```

Azure ポータルの KE20RG リソースグループの配下に、azureci コンテナインスタンスが作成されるので、
そこから、各コンテナの状態を確認することができます。
azureci コンテナインスタンスの Public IP アドレスにブラウザから HTTP アクセスすると、
Kompira Enterprise のログイン画面が表示されるので、ログインすることができます。

#### システムの削除

以下でコンテナを削除します。
```
docker compose down
```

※ ACI の docker context では、stop は未サポートです。コンテナを削除ではなく停止したい場合は、
Azure ポータルの azureci コンテナインスタンスの画面から停止してください。

