# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

このディレクトリには、AWS Elastic Container Service (AWS ECS) の [Fargate](https://aws.amazon.com/fargate/) にデプロイするための CloudFormation テンプレートファイルおよび関連ファイルが含まれています。これらは、KE2 の外部 DB シングル構成向けに準備されたものです。なお、AWS Fargate はサーバーレスサービスですが、基盤 OS は Linux であり、KE2 の Docker イメージのプラットフォームは linux/amd64 です。

## 事前準備

デプロイ作業を行うために、以下の準備をしてください。

1. AWS CLI のインストール:  
  [AWS CLI インストールガイド](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) を参考に、お使いの OS に AWS CLI をインストールします。
  
    ※ デプロイ後、コンテナにアクセスしたい場合は、[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)必要です。
  

2. ke2-docker リポジトリのファイル一式を取得:  
  https://github.com/fixpoint/ke2-docker から、Code -> Download ZIP を選択し、
  ke2-docker リポジトリのファイル一式を取得して、作業用 PC の適当なディレクトリに展開します。

3. Docker のインストール (オプショナル):  
  SSL (self-signed) 証明書の生成を行なうためには Docker が必要です。 
  [Docker インストールガイド](https://docs.docker.com/engine/install/) を参考に、お使いの OS に Docker をインストールします。

## デプロイ手順

### AWS 上に各種リソース作成

AWS 上に以下に示すの各種リソースを作成していきます。
(作成するリソースの名前は適宜変更してください)

- PostgreSQL DB インスタンス  (Aurora and RDS): pg-ke2
- Elastic File System (Amazon EFS): ke2-efs

### AWS 認証情報を使用してCLIを設定: 

あらかじめ、Identity and Access Management (IAM) から以下の情報を取得してください。

- AWS Access Key ID
- AWS Secret Access Key
- Default region name

次に、以下の認証情報を使用して CLI を設定してください。

```bash
$ aws configure
AWS Access Key ID [None]: **********************
AWS Secret Access Key [None]: **********************
Default region name [None]: ap-northeast-1  # note: Asia pacific(tokyo)
Default output format [None]: json  
```   

以下のコマンドで設定状態を確認できます:
```bash
$ aws configure list
```

### PostgreSQL DB インスタンスの作成

AWS管理コンソールにログインして、同じリージョン (ap-northeast-1) に Aurora and RDS > Databases リソースを
以下のパラメータで作成します。

データベースの作成:
- データベース作成方法を選択: 標準作成
- エンジンのオプション: PostgreSQL
- エンジンバージョン: PostgreSQL 16.8-R1
- テンプレート: 必要に応じて適切なプランを選択してください
- 可用性と耐久性: 
   - デプロイオプション: シングル AZ DB インスタンスデプロイ (1 インスタンス)
- 設定
   - DB クラスター識別子: pg-ke2
- 認証情報の設定
   - マスターユーザー名: kompira
   - 認証情報管理: セルフマネージド
   - マスターパスワード: 適切なパスワードを指定してください
   - マスターパスワードを確認: 適切なパスワードを指定してください
- 接続 
   - Virtual Private Cloud (VPC): 新しい VPC の作成
   - パブリックアクセス: あり 「AWS サービスにこのサーバーへのパブリック アクセスを許可する」
   - VPC セキュリティグループ (ファイアウォール): 新規作成
   - 新しい VPC セキュリティグループ名: pg-ke2-sg
- その他のモニタリング設定
   - ログのエクスポート: PostgreSQL ログ 「必要に応じて適切なオプションを選択してください」
   - DevOps Guru: チェックなし
- 追加設定
   - 追加設定
     - 最初のデータベース名: kompira

> [!NOTE]
> その他のパラメータはデフォルトで構いません。ただし、必要に応じて要件に合わせて変更することもできます。VPC、サブネット、セキュリティグループ（ポート5432が開いている）の設定については、カスタム設定を使用しても構いませんが、必ずKE2アプリからアクセス可能であることを確認してください。

DB インスタンスの起動にはしばらく時間がかかる場合があります。

以下のコマンドを実行して、データベースにアクセスできるかどうかを確認してください。
```bash
$ psql -h <DB インスタンスエンドポイント> -p 5432 -U kompira -d kompira
```

> [!TIP]
> 上の通りに DB インスタンスを作成後、DB インスタンス詳細ページに行って、「接続とセキュリティ」タブ中からエンドポイントを習得してください。

■ PGCRYPTO の有効化
```bash
# login
$ psql -h <DB インスタンスエンドポイント> -p 5432 -U kompira -d kompira
# activate pgcrypto extension
kompira=> CREATE EXTENSION IF NOT EXISTS pgcrypto;
# check the status
kompira=> \dx
```

### 共有ファイルストレージの作成(EFS):

Elastic Container Service(ECS) で必要となる共有ファイルストレージを以下の名称で作成しておきます。

```bash
$ aws efs create-file-system --creation-token ke2-efs --query 'FileSystemId' --tags Key=Name,Value=ke2-efs --output text
```
> [!NOTE] 
> ke2-efs ファイルストレージ ID を保存してください、ファイルのアップロードやデプロイなど時に必要となる。`efs-id: fs-*******`

### 共有ファイルストレージにファイルのアップロードの準備

EFSにファイルをアップロードする方法はいくつかあり、たとえばAWS DataSync、AWS Transfer、またはEC2インスタンスにEFSをマウントする方法などがあります。異なる方法を使用しても構いませんが、ディレクトリおよびファイルの階層は以下の通りです。

```txt
/ (EFS root)
├── configs/
│   ├── rabbitmq-conf/
│   │   ├── 20-auth.conf   (copy from ../../../../configs/rabbitmq-auth.conf)
│   │   └── 30-ssl.conf    (copy from ../../../../configs/rabbitmq-ssl.conf)
│   └── nginx-conf/
│       └── default.conf.template   (copy from ../../../../configs/nginx.conf)
├── ssl-cert/
│   ├── local-ca.crt     (copy from ../../../../ssl/local-ca.crt)
│   ├── server.crt       (copy from ../../../../ssl/server.crt)
│   └── server.key       (copy from ../../../../ssl/server.key)
└── kompira-var/
```

継続的な同期が不要な一度限りのアップロードの場合、最も簡単な方法は、EC2インスタンスにEFSをマウントし、標準のコマンドを使ってディレクトリを作成し、ファイルをコピーすることです。以下の手順を用いて、共有ファイルストレージ(EFS)をEC2にマウントしています。

#### EC2にアクセスするためのキーペアの作成
```bash
$ cd ke2/cloud/awsecs/fargate
$ aws ec2 create-key-pair --key-name KE2ECSKeyPair --query 'KeyMaterial' --output text > KE2ECSKeyPair.pem
$ chmod 400 "KE2ECSKeyPair.pem"
```

#### Amazon Linux 2 ECS-最適化AMIの推奨イメージ ID の取得
```bash
$ aws ssm get-parameters --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id --query "Parameters[0].Value" --output text
```
> [!NOTE] 
> イメージ ID を保存してください、EC2をデプロイ時に必要となる。`ec2-ami-id: ami-*******`

#### EC2インスタンスの起動とパブリックIPアドレスの取得

上のステップで習得した `ec2-ami-id` と `efs-id` を用いて、下記のコマンドで EC2 インスタンスを立ち上がります。

```bash
$ cd ke2/cloud/awsecs/fargate
$ aws cloudformation create-stack \
  --stack-name KE2EFSFUPEC2Stack \
  --template-body file://uploader.json \
  --parameters ParameterKey=KeyName,ParameterValue=KE2ECSKeyPair \
    ParameterKey=InstanceImageId,ParameterValue=<ec2-ami-id> \
    ParameterKey=EFSFileSystemId,ParameterValue=<efs-id>
```
> [!WARNING] 
> インスタンスの起動にはしばらく時間がかかる場合があります。

EC2がEFSのマウントターゲットとして正しく登録されているかどうかを確認します。MountTargetsが空でなければ問題ありません。
```bash
$ aws efs describe-mount-targets --file-system-id <efs-id>
```

立ち上げたインスタンスの ID を習得します。
```bash
$ aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=KE2EFSFUPEC2Stack" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text
```
> [!NOTE] 
> インスタンス ID を保存してください、次のステップに利用します。 `ec2-instance-id: i-******`

パブリックIPアドレスを習得します。
```bash
aws ec2 describe-instances \
  --instance-ids <ec2-instance-id> \
  --query "Reservations[].Instances[].{State:State.Name, PublicIP:PublicIpAddress}" \
  --output table
```
> [!NOTE] 
> パブリックIPアドレスを保存してください。ファイルのアップロード時に必要となる。`ec2-instance-ip: XX.XX.XX.XX`

#### 共有ファイルストレージ(EFS)のEC2へのマウントと必要なディレクトリの作成

```bash
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@13.231.238.175 "sudo mount -t efs -o tls fs-064594ea74b991a84:/ /mnt/efs"
# マウント状況を確認
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@13.231.238.175 "mount | grep /mnt/efs"
# 正しくマウントできれば以下の通りに結果もらいます。
# 127.0.0.1:/ on /mnt/efs type nfs4 (rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,namlen=255,hard,noresvport,proto=tcp,port=20636,timeo=600,retrans=2,sec=sys,clientaddr=127.0.0.1,local_lock=none,addr=127.0.0.1)
```

必要なディレクトリを作成します。`ec2-instance-ip`を用いて、以下のコマンドを実行します。

```bash
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@<your ec2-instance-ip> "sudo mkdir -p /mnt/efs/configs/rabbitmq-conf /mnt/efs/configs/nginx-conf /mnt/efs/ssl-cert /mnt/efs/kompira-var"
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@<your ec2-instance-ip>  "sudo chown -R ec2-user:ec2-user /mnt/efs"
```

#### 証明書ファイルのアップロード手順

SSL (self-signed) 証明書の生成を行なうために、以下のコマンドを実行します。

```
$ cd ke2/cloud/azureci
$ ../../../scripts/create-cert.sh
```
作成された SSL 証明書は ssl ディレクトリに保存されます。
> [!WARNING] 
> 本番環境では、証明書認証局（CA）から証明書を取得してください。

作成した ssl-cert 共有ファイルストレージ(EFS)に以下のコマンドを使用して証明書ファイルをアップロードします。

```bash
# CA 証明書のローカルパス: ../../../../ssl/local-ca.crt
$ scp  -i "KE2ECSKeyPair.pem" ../../../../ssl/local-ca.crt ec2-user@<ec2-instance-ip>:/mnt/efs/ssl-cert
# サーバーキーのローカルパス: ../../../../ssl/server.key
$ scp  -i "KE2ECSKeyPair.pem" ../../../../ssl/server.key ec2-user@<ec2-instance-ip>:/mnt/efs/ssl-cert
# サーバー証明書のローカルパス: ../../../../ssl/server.crt
$ scp  -i "KE2ECSKeyPair.pem" ../../../../ssl/server.crt ec2-user@<ec2-instance-ip>:/mnt/efs/ssl-cert
```
> [!CAUTION]
> `ec2-instance-ip`は実際のIPアドレスに置き換えてください。

#### NginxとRabbitMQ の conf ファイルのアップロード

AWS CLI の以下のコマンドで ke2-docker に含まれる NginxとRabbitMQ の conf ファイルをアップロードします。

```bash
$ scp  -i "KE2ECSKeyPair.pem" ../../../../configs/rabbitmq-auth.conf ec2-user@<ec2-instance-ip>:/mnt/efs/configs/rabbitmq-conf/20-auth.conf
$ scp  -i "KE2ECSKeyPair.pem" ../../../../configs/rabbitmq-ssl.conf ec2-user@<ec2-instance-ip>:/mnt/efs/configs/rabbitmq-conf/30-ssl.conf
$ scp  -i "KE2ECSKeyPair.pem" ../../../../configs/nginx.conf ec2-user@<ec2-instance-ip>:/mnt/efs/configs/nginx-conf/default.conf.template
```
> [!CAUTION]  
> `ec2-instance-ip` は実際のIPアドレスに置き換えてください。

#### EC2から共有ファイルストレージ（EFS）のアンマウント

```bash
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@<your ec2-instance-ip> "sudo umount -l /mnt/efs"
# アンマウント状況を確認します。正しくアンマウントされれば、何も表示されません。
$ ssh -i "KE2ECSKeyPair.pem" ec2-user@<your ec2-instance-ip> "mount | grep /mnt/efs"
```
> [!CAUTION]  
> `ec2-instance-ip` は実際のIPアドレスに置き換えてください。

#### EC2インスタンスと関連リソースの削除

```bash
aws cloudformation delete-stack --stack-name KE2EFSFUPEC2Stack
```
> [!WARNING]
> インスタンスの終了にはしばらく時間がかかる場合があります。

EFSのマウントターゲットが空になるまで待機
```bash
$ aws efs describe-mount-targets --file-system-id <efs-id>
```
> [!CAUTION]  
> `efs-id` は実際の ke2-efs ファイルストレージ IDに置き換えてください。

### アプリケーションを AWS ECS にデプロイ

`ke2-docker/ke2/cloud/awsecs` ディレクトリ上で AWS CLI を使用して CloudFormation テンプレート `deployment.json` をデプロイします。

`parameters.json` ファイルを使用して必要な値を設定します。

■ デプロイパラメータの説明は、以下の通りです。

- `UseCustomVpc`: 既存のVPCを利用する場合は `true` と指定してください。既存VPCを使用しない場合（新規作成する場合）は `false`（デフォルト: `false`）
  - 【`UseCustomVpc` が `true` の場合】
    - `CustomVpcId`: 既存の VPC ID を指定してください。
    - `CustomPublicSubnetId`: 既存の VPC 内のパブリックサブネットの ID を指定してください。
  - 【`UseCustomVpc` が `false` の場合】
    - `VpcCIDR`: VPC の CIDR ブロックを指定してください（デフォルト: `10.0.0.0/16`）
    - `PublicSubnetCIDR`: パブリックサブネットの CIDR ブロックを指定してください（デフォルト: `10.0.1.0/24`）
- `UseECSService`: コンテナタスクのデプロイを自動的に管理するために、ECSService リソースを利用する場合は `true` と指定してください。手動でコンテナタスクのデプロイを管理したい場合は `false` と指定してください（デフォルト: `true`）。
  - 【`UseECSService` が `true` の場合】: ECSService リソースがデプロイされ、コンテナタスクの状態を監視し、問題が発生したタスクを停止して新しいタスクを起動するなど、タスクの自動管理を行います。
  - 【`UseECSService` が `false` の場合】: ECSService リソースはデプロイされず、コンテナタスクのデプロイを手動またはカスタムな方法で管理する機会が提供されます。
- `ImageTag`: イメージのタグ（デフォルト:  ke2-docker 更新時点で公開されていた最新の kompira コンテナイメージのタグ。例えば "2.0.2" など）
- `TimeZone`: タイムゾーン（デフォルト: `Asia/Tokyo`）
- `MaxExecutors`: 最大エグゼキュター数（デフォルト: `2`）
- `DatabaseURL`: データベースの接続 URL 
  形式：pgsql://<ユーザ名>:<パスワード>@<アドレス・pg-ke2で始まる、PostgreSQL インスタンスのエンドポイント>:<ポート番号>/<データベース名>
> [!TIP]
> PostgreSQL インスタンスのエンドポイントとは、データベースに接続するためのDNS名またはIPアドレスのことです。AWS RDSなどのマネージドサービスを使用している場合、エンドポイントはAWS管理コンソールのDBインスタンス詳細ページで確認できます。

- `LogDriver`: Fargateのログサービス(オプション: `none`, `awslogs` デフォルト: `awslogs`)
- `LogGroupName`: ログが保存されるCloudWatch Logsグループの名前(デフォルト: `ecs-fargate/ke2`)
- `EFSFileSystemId`: 作成した `ke2-efs` ファイルストレージ ID (取得した `efs-id` を利用してください)


#### システムの起動

`ke2-docker/ke2/cloud/awsecs` ディレクトリ上で AWS CLI を使用して CloudFormation テンプレートのデプロイ。

■ 少なくとも、以下のデプロイパラメータを設定してデプロイ

- `DatabaseURL`: `pgsql://<PostgreSQLユーザ名>:<PostgreSQLパスワード>@<pg-ke2で始まる、PostgreSQL インスタンスのエンドポイント/DB IP>:5432/kompira` 
> [!CAUTION]  
> `<PostgreSQLユーザ名>`、`<pg-ke2で始まる、PostgreSQL インスタンスのエンドポイント/DB IP>` および `<PostgreSQLユーザのパスワード>` は、実際の値に置き換えてください。

- `EFSFileSystemId`: 作成した `ke2-efs` ファイルストレージ ID (取得した `efs-id` を利用してください)
- `UseECSService`: `true`（コンテナタスクのデプロイを自動的に管理する）。`UseECSService` が `false` の場合は、以下のコマンドでコンテナタスクはデプロイされず、ECS Fargate 環境のみが準備されるため、後で手動でコンテナタスクをデプロイしてください。

```bash
$ aws cloudformation create-stack \
  --stack-name KE2ECSFargateStack \
  --template-body file://deployment.json \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```
> [!WARNING]
> AWS Fargate システムの起動にはしばらく時間がかかります。

既存のAWS CloudFormationスタックをパラメータの変更で更新することにより、CloudFormationで管理されているリソースを削除せずに変更できます。更新が失敗した場合、CloudFormationは自動的に以前の状態にロールバックします。たとえば、Kompiraのイメージタグ、最大エグゼキュータ数、ログドライバーなどを更新したい場合、リソースを削除して再作成するのではなく、スタックを更新する方が良いです。

```bash
$ aws cloudformation update-stack \
  --stack-name KE2ECSFargateStack \
  --template-body file://deployment.json \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```
> [!CAUTION]  
> スタックを更新すると、以前のタスク（コンテナ）が停止し、新しいタスクが作成されます。その結果、パブリックIPが自動的に変更されます。

■ `UseECSService` が `false` の場合、以下の手順でコンテナタスクの手動デプロイ

手動デプロイてめに、以下のコマンドで必要な情報習得します。AWS管理コンソールの CloudFormation > Stacks > KE2ECSFargateStack > Outputsでも習得できます。
```bash
$ aws cloudformation describe-stacks --stack-name KE2ECSFargateStack --query "Stacks[0].Outputs" --output table
```

コンテナタスクの手動デプロイ
```bash
$ aws ecs run-task \
  --cluster KE2FargateCluster \
  --task-definition KE2Task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=["<PublicSubnetId>"],securityGroups=["<ServiceSecurityGroup ID>"],assignPublicIp=ENABLED}" \
  --count 1 \
  --enable-execute-command
```

コンテナにアクセスしたい場合は、`--enable-execute-command` オプションを使用してください。
> [!CAUTION] 
> `<PublicSubnetId>`、`<ServiceSecurityGroup ID>` は、実際の値に置き換えてください。


デプロイ後、AWS管理コンソールの ECS > Clusters > KE2FargateCluster > Services リソースの配下に、KE2FargateService > Tasks が作成されるので、そこから、各コンテナの状態を確認することができます。
KE2 コンテナインスタンスのタスクの Public IP アドレスにブラウザから HTTP・HTTPS アクセスすると、Kompira Enterprise のログイン画面が表示されるので、ログインすることができます。

> [!TIP]
> AWS管理コンソールの ECS > Clusters > KE2FargateCluster > Services(table) > Deployment and Tasks(column) > Tasks(table) > Task(Running) > Networking(tab) > Public IP の所から Public IP を習得できます。

#### コンテナログの確認

特定のコンテナのログを確認するには、以下のコマンドを実行します。

■ コンテナ名
- kompira
- kengine
- jobmngrd
- redis
- rabbitmq
- nginx

```bash
$ aws logs tail "<ロググループ名>" --log-stream-name-prefix "<コンテナ名>"
# ex: aws logs tail "ecs-fargate/ke2" --log-stream-name-prefix "kompira"
```
> [!CAUTION] 
> `<ロググループ名>`, および `<コンテナ名>` は、実際の値に置き換えてください。

> [!TIP]
> AWS管理コンソールの ECS > Clusters > KE2FargateCluster > Services リソースの配下に、KE2FargateService > Tasks、または CloudWatch からもログを確認できます。

#### コンテナへのシェルアクセス

特定のコンテナにシェルアクセスするには、以下のコマンドを実行します。

```bash
$ aws ecs execute-command \
  --cluster KE2FargateCluster \
  --task <タスク ID/ARN> \
  --container <コンテナ名> \
  --interactive \
  --command "/bin/sh"
```
> [!CAUTION] 
> `<コンテナ名>`, および `<タスク ID/ARN>` は、実際の値に置き換えてください。

以下のコマンドでタスク ARNを習得できます。
```bash
$ aws ecs list-tasks --cluster KE2FargateCluster --desired-status RUNNING --launch-type FARGATE --query "taskArns[]" --output text
```
> [!TIP]
> AWS管理コンソールの ECS > Clusters > KE2FargateCluster > Services リソースの配下に、KE2FargateService > Tasks からも習得できます。

#### システムの削除・停止

■ 削除
- `UseCustomVpc` が `false` の場合、以下のコマンドで、VPC から ECSクラスターおよび関連リソース、コンテナ、ログまで削除します。
- `UseCustomVpc` が `true` の場合、以下のコマンドで、ECSクラスターおよび関連リソース、コンテナ、ログまで削除します。

```bash
$ aws cloudformation delete-stack --stack-name KE2ECSFargateStack
```

`UseECSService` が `false` の場合、コンテナタスクは ECS サービスによって自動的に管理されないため、実行中のタスクが存在する場合、KE2ECSFargateStack の ECS クラスターおよび関連リソースを削除することはできません。その場合は、まず以下のコマンドを使用してコンテナタスクを停止してください。

```bash
# <タスク ID/ARN>は、実際の値に置き換えてください。
$ aws ecs stop-task --cluster KE2FargateCluster --task <タスク ID/ARN>
```


KE2ECSFargateStackまたはKE2FargateClusterを削除ではなくコンテナタスクのみ停止・起動したい場合は、以下のコマンドも利用できます。

■ 停止

`UseECSService` が `true` の場合、コンテナタスクを直接に停止してもECSServiceで自動的に新タスクが起動されます。
なので以下のコマンドでコンテナタスクを停止します。
```bash
$ aws ecs update-service --cluster KE2FargateCluster --service KE2FargateService --desired-count 0
```


`UseECSService` が `false` の場合、以下のコマンドでコンテナタスクを停止できます。
```bash
$ aws ecs stop-task --cluster KE2FargateCluster --task <タスク ID/ARN>
```

■ 起動・再起動

AWS Fargate はコンテナタスクの再起動機能をネイティブにサポートしていません。run-task および stop-task のみがサポートされており、run-task コマンドを実行すると新しいタスクが起動されます。

`UseECSService` が `true` の場合、以下のコマンドでコンテナタスクを起動できます。
```bash
$ aws ecs update-service --cluster KE2FargateCluster --service KE2FargateService --desired-count 1
```


`UseECSService` が `false` の場合、以下のコマンドでコンテナタスクを起動できます。
```bash
$ aws ecs run-task \
  --cluster KE2FargateCluster \
  --task-definition KE2Task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=["<PublicSubnetId>"],securityGroups=["<ServiceSecurityGroup ID>"],assignPublicIp=ENABLED}" \
  --count 1 \
  --enable-execute-command
```

コンテナにアクセスしたい場合は、`--enable-execute-command` オプションを使用してください。
> [!CAUTION] 
> `<PublicSubnetId>`、`<ServiceSecurityGroup ID>` は、実際の値に置き換えてください。

## 料金プラン
■ このデプロイメントでは、以下のスペックを使用します。
- vCPU リソース：4 コア
- メモリ：16GB
- OS: Linux
- CPUアーキテクチャ: x86
- タスクまたはポッドの数: 1

プランについては、[このリンクをご参照ください。](https://calculator.aws/#/createCalculator/Fargate)

■ aws log を利用する場合、 AWS CloudWatch のコストも別途追加となります。プランについては、[このリンクをご参照ください。](https://aws.amazon.com/cloudwatch/pricing)

■ AWS RDS インスタンス(PostgeSQL)を利用する場合、 RDS インスタンスのコストも別途追加となります。

PostgreSQL インスタンステンプレートがプロダクション(1 インスタンス)の場合、デフォルトのスペックは以下の通りです。

- DB インスタンスクラス: db.m7g.large
- デプロイオプション: Single-AZ
- ストレージボリューム:  IOPS SSD IO2
- ストレージ量: 400 GiB

> [!NOTE]  
> ストレージ容量は 400 GiBとなっていますが、用途に応じて変更いただいても問題ありません。

プランについては、[このリンクをご参照ください。](https://calculator.aws/#/createCalculator/RDSPostgreSQL)

