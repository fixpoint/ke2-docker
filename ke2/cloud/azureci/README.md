# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

このディレクトリには Azure Container Instances (ACI) にデプロイするための ARM template ファイルが含まれています。

## 事前準備

デプロイ作業を行うために、以下の準備をしてください。

1. Azure CLI のインストール:  
  [Azure CLI インストールガイド](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli) を参考に、お使いの OS に Azure CLI をインストールします。
  

2. ke2-docker リポジトリのファイル一式を取得:  
  https://github.com/fixpoint/ke2-docker から、Code -> Download ZIP を選択し、
  ke2-docker リポジトリのファイル一式を取得して、作業用 PC の適当なディレクトリに展開します。

3. Docker のインストール (オプショナル):  
  SSL (self-signed) 証明書の生成を行なうためには Docker が必要です。 
  [Docker インストールガイド](https://docs.docker.com/engine/install/) を参考に、お使いの OS に Docker をインストールします。

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
az account list --output table
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
- rabbitmq-conf: RabbitMQ 設定ファイル用
- ssl-cert: SSL・CA 証明書用
- kompira-log: kompira のログファイル用
- kompira-share: kompira コンテナ内の特定のパスにマウント用 (オプショナル)

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

az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name rabbitmq-conf

az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name ssl-cert

az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name kompira-log

# オプショナル
# kompira コンテナで (export_dir や import_dir など）のデータ管理を行う予定がある場合は、事前に作成しておいてください。
az storage share-rm create \
  --resource-group KE20RG \
  --storage-account ke20storage \
  --name kompira-share
```

#### 証明書ファイルのアップロード手順

SSL (self-signed) 証明書の生成を行なうために、以下のコマンドを実行します。

```
$ cd ke2/cloud/azureci
$ ../../../scripts/create-cert.sh
```
作成された SSL 証明書は ssl ディレクトリに保存されます。

※ 本番環境では、証明書認証局（CA）から証明書を取得してください。

作成した ssl-cert 共有ボリュームに以下のコマンドを使用して証明書ファイルをアップロードします。

```
az storage file upload --account-name ke20storage -s ssl-cert --source <サーバー証明書のローカルパス> -p server.crt

az storage file upload --account-name ke20storage -s ssl-cert --source <サーバーキーのローカルパス> -p server.key

az storage file upload --account-name ke20storage -s ssl-cert --source <CA 証明書のローカルパス> -p local-ca.crt
```

注意: `<サーバー証明書のローカルパス>`, `<サーバーキーのローカルパス>`, および `<CA 証明書のローカルパス>` は、それぞれの証明書ファイルが保存されているローカルパスに置き換えてください。

Azure ポータルにログインして、ke20storage ストレージアカウントのファイル共有 kompira-nginx-conf に移動し、
画面上からアップロードすることも可能です。


#### Nginx の conf ファイルのアップロード

Nginx の conf ファイルを kompira-nginx-conf ボリュームに default.conf という名称でアップロードします。

Azure CLI の以下のコマンドで ke2-docker に含まれる Nginx の conf ファイルをアップロードします。

```
cd .\ke2-docker
az storage file upload --account-name ke20storage -s kompira-nginx-conf --source ./configs/nginx.conf -p default.conf.template
```

Azure ポータルにログインして、ke20storage ストレージアカウントのファイル共有 kompira-nginx-conf に移動し、
画面上からアップロードすることも可能です。


#### RabbitMQ の conf ファイルのアップロード

以下のコマンドを使用して、RabbitMQ の conf ファイルを rabbitmq-conf ボリュームにアップロードします。

```
cd .\ke2-docker

az storage file upload --account-name ke20storage -s rabbitmq-conf --source ./configs/rabbitmq-auth.conf -p 20-auth.conf

az storage file upload --account-name ke20storage -s rabbitmq-conf --source ./configs/rabbitmq-ssl.conf -p 30-ssl.conf
```

Azure ポータルにログインして、ke20storage ストレージアカウントのファイル共有 kompira-nginx-conf に移動し、
画面上からアップロードすることも可能です。

#### Log Analytics ワークスペースの作成 (オプショナル)
一般的に、KE2 コンテナが実行中の場合、コンソールログは Azure ポータルまたは Azure CLI からアクセス可能です。しかし、Azure 上で KE2 を再起動または再デプロイすると、以前のコンソールログは削除されます。そのため、コンソールログを保持したい場合は、Azure Log Analytics ワークスペースにログを保存する必要があります。

※ Azure Log Analytics ワークスペースの使用は必須ではありませんが、問題発生時の解析のため、本番環境においては使用を推奨します。

すでに Azure Log Analytics ワークスペースがある場合は、新しく作成せずにそれを使用できます。以下のコマンドを使用して Azure Log Analytics ワークスペースを作成します。

```bash
az monitor log-analytics workspace create \
  --resource-group KE20RG \
  --workspace-name ke2-azure-ci-log-space
```

Azure Log Analytics ワークスペースに対する操作には、「ワークスペースID」と共有キーのうち「主キー」が必要になります。KE2 をデプロイする際に「ワークスペース ID」と「主キー」を渡す必要があるため、以下の手順でそれらの値を事前に確認しておいてください。

ワークスペース ID を取得:

```bash
az monitor log-analytics workspace show \
  --resource-group KE20RG \
  --workspace-name ke2-azure-ci-log-space \
  --query customerId \
  --output tsv
```

主キー を取得(primarySharedKey):

Azure Log Analytics ワークスペースを作成すると「共有キー」が生成されます。共有キーには「主キー」と「2次キー」という２つのキーがあり、前者のことを "primarySharedKey" と、後者のことを "secondarySharedKey" と言います。以下の get-shared-keys コマンドを実行することで２つの共有キーを取得することができます。主キー (primarySharedKey) の値を確認しておいてください。

```bash
az monitor log-analytics workspace get-shared-keys \
  --resource-group KE20RG \
  --workspace-name ke2-azure-ci-log-space

# output:
#{
#  "primarySharedKey": "*******",
#  "secondarySharedKey": "********"
#}
```

[Log Analytics ワークスペースの概要](https://learn.microsoft.com/ja-jp/azure/azure-monitor/logs/log-analytics-workspace-overview)をご参照ください。

### アプリケーションを ACI にデプロイ

ke2-docker/ke2/cloud/azureci ディレクトリ上で Azure CLI を使用して ARM テンプレート aci-deployment.json をデプロイします。

aci-parameters.json ファイルを使用して必要な値を設定します。以下のフィールドを更新します。

- `<database-url>`: `pgsql://<PostgreSQLユーザ名>:<PostgreSQLパスワード>@postgresql-for-ke.postgres.database.azure.com:5432/kompira` 
  注意: <PostgreSQLユーザ名> および <PostgreSQLユーザのパスワード> は、実際のユーザー名とパスワードに置き換えてください。
- `<storage-account-name>`: `ke20storage` (作成するリソースの名前は適宜変更してください)
- `<storage-account-key>`: 取得したストレージアカウントキー

ストレージアカウントキーは以下のコマンドを使用して取得できます。

```
az storage account keys list --resource-group KE20RG --account-name ke20storage --output table
```

#### システムの起動

ke2-docker/ke2/cloud/azureci ディレクトリ上で Azure CLI を使用して ARM テンプレートのデプロイ。
```
> cd ./ke2-docker/ke2/cloud/azureci
> az deployment group create \
  --resource-group KE20RG \
  --template-file aci-deployment.json \
  --parameters @aci-parameters.json
```

Azure ポータルの KE20RG リソースグループの配下に、azureci コンテナインスタンスが作成されるので、
そこから、各コンテナの状態を確認することができます。
azureci コンテナインスタンスの Public IP アドレスにブラウザから HTTP・HTTPS アクセスすると、Kompira Enterprise のログイン画面が表示されるので、ログインすることができます。

デプロイ時にパラメータをオーバーライドすることも可能です。
```
az deployment group create \
  --resource-group KE20RG \
  --template-file aci-deployment.json \
  --parameters @aci-parameters.json \
  --parameters databaseUrl=<database-url> \
  --parameters storageAccountName=<storage-account-name> \
  --parameters storageAccountKey=<storage-account-key>
  ```

オーバーライドできるパラメータは以下のとおりです。

- imageTag: イメージのタグ（デフォルト:  ke2-docker 更新時点で公開されていた最新の kompira コンテナイメージのタグ。例えば "2.0.2" など）
- timezone: タイムゾーン（デフォルト: "Asia/Tokyo"）
- maxExecutor: 最大エグゼキュター数（デフォルト: 2）
- dnsNameLabel: DNS 名ラベル（デフォルト: 空）。
  DNS 名ラベルを追加する場合、`<dnsNameLabel>`.japaneast.azurecontainer.io にブラウザからアクセスできます。
- databaseUrl: データベースの接続 URL 
  形式：pgsql://<ユーザ名>:<パスワード>@<アドレス>:<ポート番号>/<データベース名>
- storageAccountName: ストレージアカウント名(デフォルト: ke20storage)
- storageAccountKey: 取得したストレージアカウントキー

Azure Log Analytics ワークスペースに対する操作には、「ワークスペースID」と共有キーのうち「主キー」が必要になります。KE2 のコンソールログを Azure Log Analytics ワークスペースに送信する場合は、以下のパラメーターの値を指定してください。
- logAnalyticsWorkspaceId: 取得した Azure Log Analytics 「ワークスペース ID」 (デフォルト: 空)
- logAnalyticsKey: 取得した Azure Log Analytics の「主キー」(primarySharedKey) (デフォルト: 空)

また KE2 ACI を既存のサブネット内にデプロイすることもできます。

> **重要:**  
> I) 本構成では、KE2 をデプロイした直後はパブリック IP や DNS 名からはアクセスできず、プライベートネットワーク内のプライベート IP を経由してのみ接続可能です。<br/>
> II) プライベート IP は、指定したサブネットのアドレス範囲から自動的に割り当てられます。<br/>
> III) パブリックに公開したい場合、Azure サービス (Azure Firewall や NAT Gateway や Application Gateway など) を併用してください。

この構成を採用するには、あらかじめ 仮想ネットワーク と サブネット を作成し、KE2 を ARM テンプレートでデプロイする際に、仮想ネットワーク名とサブネット名を以下のパラメーターの値を指定してください。

- vnetName: 作成した仮想ネットワーク名(デフォルト: 空)
- subnetName: 作成したサブネット名(デフォルト: 空)

注意: サブネットを作成する際は、サブネットの委任設定として 「Microsoft.ContainerInstance/containerGroups」 を選択する必要があります。


多くの場合、コンテナと Azure ポータルまたはローカルマシン間でデータを共有(インポートやエクスポートなどの時)の必要があります。Azure CI はクラウド上でコンテナを実行するため、Azure プラットフォームやローカルマシンとコンテナ間で直接データを共有することは一般的にできません。そのため、Azure File Share を使用してコンテナ内のパスをマウントする必要があります。以下のパラメーターを使用することで、kompira コンテナ内のマウント先パスを指定できます。
- kompiraSharePath: kompira コンテナ内のマウント先パス(デフォルト: "")。デフォルトでは空("")のでマウントされません。マウントしたい場合、事前に Azure ファイル共有 `kompira-share` を作成し、このパラメーターも指定してください。

  ※ マウントのために、Kompira コンテナ内の任意の既存のディレクトリパスを指定することができます。推奨されるパスは `"/mnt"` です。
  もし別のディレクトリ例えば `/usr/src`、`/opt/kompira`、`/var/opt/kompira` をマウント先として使用したい場合は、エクスポート・インポートなどの操作を行う時に、マウントディレクトリ内に新しいディレクトリを作成し、そちらに操作実行ほうが安全です。

#### 実行中コンテナログの確認

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

以下のコマンドでもログをダウンロードできます。
```bash
az container logs --resource-group KE20RG --name azureci --container-name <コンテナ名> --output table > <コンテナ名>.log
```

#### Log Analytics によるコンテナログの確認

Log Analytics からログを収集するために Log Analytics ワークスペース ID が必要です。そのため、事前にワークスペース ID を取得しておいてください。

最後の数行ログを取得:
```bash
# 以下のコマンド実行前 <logAnalyticsWorkspaceId>、<コンテナ名>、<lines> を実際の値に置き換えてください。
az monitor log-analytics query \
  --workspace <logAnalyticsWorkspaceId> \
  --analytics-query "
    ContainerInstanceLog_CL
    | where ContainerName_s == '<コンテナ名>'
    | sort by TimeGenerated desc
    | take <lines>
  " \
  --output table > <コンテナ名>.log
```

特定の時間範囲でフィルター:
```bash
# 以下のコマンド実行前 <logAnalyticsWorkspaceId>、<コンテナ名>、datetime() を実際の値に置き換えてください。
az monitor log-analytics query \
  --workspace <logAnalyticsWorkspaceId> \
  --analytics-query "
    ContainerInstanceLog_CL
    | where ContainerName_s == '<コンテナ名>'
    | where TimeGenerated between (datetime(2024-12-01T00:00:00Z) .. datetime(2024-12-01T12:00:00Z))
    | sort by TimeGenerated desc
  " \
  --output table > <コンテナ名>.log
```

直近数時間のログ収集:
```bash
# 以下のコマンド実行前 <logAnalyticsWorkspaceId>、<コンテナ名>、<hours> を実際の値に置き換えてください。
# <hours>: 1h, 2h, 3h, ...24h etc.
az monitor log-analytics query \
  --workspace <logAnalyticsWorkspaceId> \
  --analytics-query "
    ContainerInstanceLog_CL
    | where ContainerName_s == '<コンテナ名>'
    | where TimeGenerated > ago(<hours>)
    | sort by TimeGenerated desc
  " \
  --output table > <コンテナ名>.log
```


Azure portal で [Log analytics のログの表示](https://learn.microsoft.com/ja-jp/azure/container-instances/container-instances-log-analytics#view-logs)をご参照ください。


#### KE2 のファイルログ(audit や process やkompira_sendevtなど) の確認

以下のコマンドを使用して、Azure ファイル共有 `kompira-log` からログファイルをダウンロードしてください。

注意: コマンド実行前 <storageAccountName>、<storageAccountKey>、<保存先のローカルフォルダ> を実際の値に置き換えてください。

```bash
for f in $(az storage file list \
--account-name <storageAccountName> \
--account-key <storageAccountKey> \
--share-name kompira-log \
--query "[?properties.contentLength!=null].name" -o tsv); \
do az storage file download \
--account-name <storageAccountName> \
--account-key <storageAccountKey> \
--share-name kompira-log \
--path "$f" --dest "<保存先のローカルフォルダ>/$f"; \
done
```

Azure ファイル共有 `kompira-log` のログファイルは、Azure ポータルから直接ダウンロードすることもできます。 

#### コンテナへのシェルアクセス

特定のコンテナにシェルアクセスするには、以下のコマンドを実行します。

```
az container exec --resource-group KE20RG --name azureci --container-name <コンテナ名> --exec-command /bin/sh
```

#### システムの削除・停止

以下でコンテナを削除します。
```
az container delete --resource-group KE20RG --name azureci --yes
```

コンテナを削除ではなく停止・起動・再起動したい場合は、以下のコマンドも利用できます。

停止:
```
az container stop --resource-group KE20RG --name azureci
```

起動:
```
az container start --resource-group KE20RG --name azureci
```

再起動:
```
az container restart --resource-group KE20RG --name azureci
```

## ローカルマシンでの Azure ファイル共有のマウント手順

Azure ポータルから Azure ファイル共有にアクセスすることもできますが、操作の都合上、ローカルにマウントして使用する方が便利な場合もあります。以下の手順で、Azure ファイル共有をローカルにマウントすることができます。

Linux マシンに `cifs-utils` がインストールされていない場合は、インストールしてください。
```
# 例:
sudo dnf install cifs-utils
```

以下のコマンドで、Azure ファイル共有をローカル環境にマウントしてください。コマンド実行前 `<storageAccountName>`、`<storageAccountKey>`、`<Azure ファイル共有名>`、`<マウント先のローカルディレクトリ>` を実際の値に置き換えてください。

```
sudo mount -t cifs //<storageAccountName>.file.core.windows.net/<Azure ファイル共有名> <マウント先のローカルディレクトリ> \
-o vers=3.0,\
username=<storageAccountName>,\
password=<storageAccountKey>,\
dir_mode=0777,file_mode=0777,serverino
```

このドキュメントに従って Azure ファイル共有を同じ名前で準備した場合、以下の Azure ファイル共有がすでに作成済みです。

Azure ファイル共有名:
- kompira-share:
  オプショナルですがこの Azure ファイル共有は、Kompira コンテナ間でデータを共有することを主な目的としています。たとえば、インポートやエクスポートの操作に利用することができます。KE2 のデプロイ時には、kompira コンテナ内のマウント先パスをパラメーター `<kompiraSharePath>` で指定可能です。`<kompiraSharePath>` に推奨パス以外を指定する場合は、既存のファイルやディレクトリに注意して取り扱ってください。それ以外の場合は、このファイル共有上で任意の操作（作成、変更、削除など）を行って問題ありません。

- kompira-log:
  この Azure ファイル共有は、kompira のログファイルを永続化することを主な目的としています。他の用途で使用することも可能ですが、その場合も既存のファイルやディレクトリの管理には注意が必要です。

その他の Azure ファイル共有（特別な理由がない限り、マウントしないことを推奨）

- kompira-var
- kompira-nginx-conf
- rabbitmq-conf
- ssl-cert

以下のコマンドでマウントしたローカルディレクトリをアンマウントすることができます。
```
sudo umount <マウント先のローカルディレクトリ>
```

## データ管理

多くの箇所で、`<kompiraSharePath>` と Azure ファイル共有 `kompira-share` の両方が登場します。基本的にこれらは同じリソースを指しており、`<kompiraSharePath>` はコンテナ内でのマウントパスを示し、`kompira-share` はそのマウントパスに接続された Azure ファイル共有を指します。`<kompiraSharePath>` で行った作業内容は、Azure ファイル共有 `kompira-share` 側にも反映されます。逆も同様で、`kompira-share` 側での変更は `<kompiraSharePath>` にも反映されます。エクスポートやインポートなどの操作を行う際は、`<kompiraSharePath>` が `kompira-share` のルートパスであることに注意してください。

Azure ファイル共有 `kompira-share` またはそのマウント先である `<kompiraSharePath>` に対して操作を行うには、以下の方法が考えられます。

- Azure ファイル共有 `kompira-share` がローカルにマウントされていれば、ディレクトリ作成やファイルのアップロード・ダウンロード、アクセスなどの操作をローカルから直接行うことができます。
- また、Azure ポータルを通じて Azure ファイル共有 `kompira-share` にアクセスし、ディレクトリの作成やファイルのアップロードなど、各種操作を実行することもできます。
- Azure CLI を使用して `kompira-share` 内に、必要な操作を行うことも可能です。以下のコマンド実行前 `<storageAccountName>`、`<storageAccountKey>` を実際の値に置き換えてください。

```
az storage <sub-commands> \
  --account-name <storageAccountName> \
  --account-key <storageAccountKey> \
  --share-name kompira-share \
  [options...]
```

`<sub-commands>`や`[options...]`に関しては、[az storage](https://learn.microsoft.com/ja-jp/cli/azure/storage?view=azure-cli-latest)をご参照ください。

```
# 例: Azure CLI で kompira-share からローカルにファイルをダウンロードする
az storage file download \
  --account-name <storageAccountName> \
  --account-key <storageAccountKey> \
  --share-name kompira-share \
  --path <kompira-shareのファイルパス> \
  --dest <保存先のローカルフォルダ>
```

- 以下のコマンドを利用することで、ローカル環境からファイルのアップロードやダウンロードは行えませんが、コンテナ内で直接コマンドを実行し、必要な操作を行うことができます。コマンドでは不要な操作を行うと、コンテナがクラッシュする可能性があるのでご注意ください。コマンド実行前 `<コンテナ名>`、`<command-to-run-inside-container>` を実際の値に置き換えてください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name <コンテナ名> \
--exec-command "<command-to-run-inside-container>"
```

```
# 例: kompira コンテナの <kompiraSharePath> に新規ディレクトリ作成
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "mkdir <kompiraSharePath>/<新規ディレクトリ名>"
```

※ [Azure Storage Explorer](https://azure.microsoft.com/ja-JP/products/storage/storage-explorer/) でも Azure ファイル共有を管理することができます。

### データのエクスポート

#### export_data 管理コマンドによるエクスポート

`export_data` 管理コマンドを用いると、指定したパス配下の Kompira オブジェクトを JSON 形式でエクスポートすることができます。 KE2 では kompira コンテナ上で `export_data` 管理コマンドを実行させるために、以下のように実行してください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py export_data [options...] <オブジェクトパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

デフォルトではエクスポートデータは標準出力に出力されるので、ローカルに書き出したい場合は、リダイレクトを利用するなどしてください。コマンド実行前 `<オブジェクトパス>` を実際の値に置き換えてください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py export_data <オブジェクトパス>" > exported_data.json
```

export_data 管理コマンドで `--zip-mode` オプションを指定した場合は、エクスポートデータはコンテナ側に ZIP ファイルとして書き出されることに注意してください。実は `<kompiraSharePath>` に ZIP ファイルとして書き出されます。深いパスにエクスポートしたい場合は、あらかじめ `<kompiraSharePath>` 内に対象ディレクトリを作成し、コマンドに `<kompiraSharePath>`代わりに`<kompiraSharePath>/<深いパス>` 形で書いてください。コマンド実行前 `<kompiraSharePath>`、`<オブジェクトパス>` を実際の値に置き換えてください。
```
> az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command /bin/sh

> cd <kompiraSharePath> && manage.py export_data --zip-mode <オブジェクトパス> && exit
```

#### export_dir 管理コマンドによるエクスポート

export_dir 管理コマンドを用いると、指定したパス配下の Kompira オブジェクトをオブジェクト毎に ディレクトリ・ファイル一式としてエクスポートすることができます。KE2 では kompira コンテナ上で export_dir 管理コマンドを実行させるために、以下のように実行してください。

```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py export_dir [options...] <オブジェクトパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

export_dir 管理コマンドではコンテナ上のファイルシステムにファイルを書き出すので、以下のようにコマンドに `--current=<kompiraSharePath>` オプションを指定する必要があります。深いパスにエクスポートしたい場合は、あらかじめ `<kompiraSharePath>` 内に対象ディレクトリを作成するのは必要となります。その場合、コマンドに `--current==<kompiraSharePath>/<深いパス>` オプションを指定してください。コマンド実行前 `<kompiraSharePath>`、`<オブジェクトパス>` を実際の値に置き換えてください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py export_dir --current=<kompiraSharePath> <オブジェクトパス>"
```


### データのインポート

#### import_data 管理コマンドによるインポート

import_data 管理コマンドを用いると、export_data 管理コマンドでエクスポートしたファイルからデータを取り込むことができます。 KE2 では kompira コンテナ上で import_data 管理コマンドを実行させるために、以下のように実行してください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira manage.py \
--exec-command "manage.py import_data [options...] <filename>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

インポートしたいファイルを Azure ファイル共有 `kompira-share` に直接配置した場合は、以下のコマンドを使用して KE2 にインポートすることができます。深いパスからインポートしたい場合は、あらかじめ `kompira-share` 内に対象ディレクトリを作成するのは必要となります。その場合、コマンドに `<kompiraSharePath>/<ファイル名>`代わりに`<kompiraSharePath>/<深いパス>/<ファイル名>` 形で書いてください。コマンド実行前に、`<kompiraSharePath>`、`<ファイル名>` は実際の値に置き換えてください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py import_data <kompiraSharePath>/<ファイル名>"
```

#### import_dir 管理コマンドによるインポート

import_dir 管理コマンドを用いると、export_dir 管理コマンドでエクスポートしたディレクトリ・ファイル一式からデータを取り込むことができます。 KE2 では kompira コンテナ上で import_dir 管理コマンドを実行させるために、以下のように実行してください。

```
az container exec --resource-group KE20RG \
--name azureci --container-name kompira \
--exec-command "manage.py import_dir [options...] <ディレクトリパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

インポートしたいディレクトリ・ファイル一式を Azure ファイル共有 `kompira-share` に直接配置した場合は、以下のコマンドを使用して KE2 にインポートすることができます。深いパスからインポートしたい場合は、あらかじめ `kompira-share` 内に対象ディレクトリを作成するのは必要となります。その場合、コマンドに `<kompiraSharePath>`代わりに`<kompiraSharePath>/<深いパス>` 形で書いてください。コマンド実行前に、`<kompiraSharePath>` は実際の値に置き換えてください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py import_dir <kompiraSharePath>"
```

※ export_data・export_dir・import_data・import_dir 管理コマンドの詳細は [Kompira Enterprise 2.0 管理者マニュアル](https://fixpoint.github.io/ke2-admin-manual/management/data/index.html)をご参照ください。

### オブジェクトのコンパイル

#### ジョブフローオブジェクトのコンパイル

以下のコマンドを実行してください。コマンド実行前に、`[options...]`, `<ジョブフロ―オブジェクトのパス>` は実際の値に置き換えてください。

```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py compile_jobflow [options...] <ジョブフロ―オブジェクトのパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

#### ライブラリオブジェクトのコンパイル

以下のコマンドを実行してください。コマンド実行前に、`[options...]`, `<ライブラリオブジェクトのパス>` は実際の値に置き換えてください。

```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py compile_library [options...] <ライブラリオブジェクトのパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。


### チャネルオブジェクトの操作

#### チャネルオブジェクトのメッセージを見る
以下のコマンドを実行してください。コマンド実行前に、`[options...]`, `<チャネルオブジェクトのパス>` は実際の値に置き換えてください。

```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py peek_channel [options...] <チャネルオブジェクトのパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

#### チャネルオブジェクトからメッセージを取り出す
以下のコマンドを実行してください。コマンド実行前に、`[options...]`, `<チャネルオブジェクトのパス>` は実際の値に置き換えてください。

```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py pop_channel [options...] <チャネルオブジェクトのパス>"
```
`[options...]`の詳細については、--help オプションを指定することで確認できます。

### プロセスオブジェクト管理

### process 管理コマンドの実行
process 管理コマンドは以下のように kompira コンテナで実行してください。
```
az container exec --resource-group KE20RG \
--name azureci \
--container-name kompira \
--exec-command "manage.py process [options...]"
```

プロセスオブジェクト管理の詳細は [Kompira Enterprise 2.0 管理者マニュアル](https://fixpoint.github.io/ke2-admin-manual/management/data/process.html) をご参照ください。

## 料金プラン
このデプロイメントでは、以下のスペックを使用します。
vCPU リソース：4 コア
メモリ：16GB
OS: Linux
SKU: Standard

プランについては、[このリンクをご参照ください。](https://azure.microsoft.com/en-us/pricing/details/container-instances/)

