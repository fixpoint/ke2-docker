# Kompira Enterprise 2.0: Swarm クラスタ構成

このディレクトリには Docker Swarm クラスタ上に複数のエンジンコンテナを
デプロイするための、Docker Compose ファイルが含まれています。

複数のエンジンコンテナを動作させることにより、パフォーマンスや可用性の
向上が期待できます。

## クラスタ環境の構築

Docker Swarm クラスタを構築するためには、同一 LAN 上に配置するホスト
（Linux サーバ）が最小で3台必要です。この 3台のホスト上にそれぞれマネー
ジャノードを起動してクラスタを構成します。さらに、PostgreSQL データベー
ス、および、各ホストが利用する共有ファイルシステムを別途用意する必要が
あります。

ここでは、Docker Swarm クラスタを構成する3台のホスト上に、
PostgreSQL/Pgpool-II のデータベースクラスタ、および、GlusterFS による
共有ファイルシステムを動作させる想定での構築手順について説明します。

### Linux サーバの準備

Docker Swarm (24.0以降)が動作する Linux サーバ 3台を準備します。各サー
バはお互いにホスト名で名前解決できるように /etc/hosts の設定を行うか、
DNS サーバに登録しておきます。

以下の設定例では、3台のホストのホスト名と IP アドレスを以下のように想
定します。

- ke2-server1: 10.20.0.1
- ke2-server2: 10.20.0.2
- ke2-server3: 10.20.0.3

また、Pgpool-II クラスタに設定する仮想 IP アドレスとして 10.20.0.100
を使用します。

なお、以下の手順では、RHEL 9 系 (CentOS Stream 9、AlmaLinux 9、
RockyLinux 9も含む) の利用を想定しています。Ubuntu など別のディストリ
ビューションを利用する場合は、適宜、コマンド等を読み替えてください。

### Docker Swarm クラスタの構築

#### Docker CE のインストール

Docker の公式リポジトリを追加し、Docker CE を各ホストにインストールし
ます。各ホスト上で以下のコマンドを実行します。

```
[全ホスト]$ sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
[全ホスト]$ sudo dnf install docker-ce
```

次に、Docker サービスの有効化と起動を行います。

```
[全ホスト]$ sudo systemctl enable --now docker
```

現在のユーザーが sudo せずに dockerコマンドを実行できるように、現在の
ユーザを docker グループに所属させます。(本手順は省略してもかまいませ
ん）

```
[全ホスト]$ sudo usermod -aG docker $USER
```

なお、上記の設定を反映させるには、一度ログアウトしてから、再度ログイン
し直す必要があります。

#### ファイアウォールの設定

以下のポートの利用が必要です。 システムの中には、デフォルトでこれらの
ポートはすでに開放されているものがあります。

- TCP ポートの 2377: クラスター管理における通信のため
- TCP および UDP ポートの 7946: ノード間の通信のため
- UDP ポートの 4789: オーバーレイネットワークのトラフィックのため

各ホスト上で、以下のコマンドを実行してポートを開放します。

```
[全ホスト]$ sudo firewall-cmd --permanent --add-port=2377/tcp
[全ホスト]$ sudo firewall-cmd --permanent --add-port=7946/tcp --add-port=7946/udp
[全ホスト]$ sudo firewall-cmd --permanent --add-port=4789/udp
[全ホスト]$ sudo firewall-cmd --reload
```

#### クラスタの初期化

最初のマネージャノード(ここでは ke2-server1 を想定)となる Docker ホス
ト上で以下を実行します。

```
[ke2-server1]$ docker swarm init
```

---
[注意] VMWare の仮想サーバでネットワークインタフェースに vmxnet3 を利
用している場合、Swarm の overlay network の 4789 番ポートと衝突し、
Swarm ノード間の TCP 通信ができない問題が報告されています。これを回避
するためには、docker swarm init に --data-path-port オプションで 4789
以外のポート番号を指定する必要があります。合わせて、ファイアウォールの
設定も、ここで指定したポートでノード間の通信を許可するように追加します。
---

続いて、以下のコマンドを実行して、マネージャノードを追加するコマンドを
取得します。

```
[ke2-server1]$ docker swarm join-token manager
```

2つ目、3つ目のDocker ホスト上で以下のコマンド(上記を実行した時に表示さ
れるコマンド)をそれぞれ実行します。

```
[ke2-server{2,3}]$ docker swarm join --token <トークン> <IPアドレス>:2377
```

任意のDockerホスト上で以下のコマンドを実行すると、Swarmクラスタに参加
しているノード一覧を表示することができます。

```
[ke2-server1]$ docker node ls
ID                            HOSTNAME        STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
ee5c0f5j5dt1m2x6vemrz7dxy *   ke2-server1     Ready     Active         Reachable        25.0.4
ypqsarfbtuwrit9hekiqac03u     ke2-server2     Ready     Active         Reachable        25.0.4
t8zhg0ez1xezj0942d7zb4u6h     ke2-server3     Ready     Active         Leader           25.0.4
```

### GlusterFS クラスタの構築

Kompira のマルチエンジン構成では、Docker Swarm 上で動作する各ホスト上
の Kompira のコンテナからアクセス可能な共有ディレクトリが必要です。す
でに、利用可能な共有ファイルサーバがある場合は、そのサーバ上のディレク
トリを Docker Swarm の各ホストからマウントして利用することもできます。
ここでは、GlusterFS 分散ファイルシステムを用いて共有ディレクトリを設定
します。

#### GlusterFS インストールと設定

各ホスト上で以下のコマンドを実行して、GlusterFS をインストールします。

```
[全ホスト]$ sudo dnf install centos-release-gluster10
[全ホスト]$ sudo dnf install glusterfs-server
```

次に、GlusterFS サービスの有効化と起動を行います。

```
[全ホスト]$ sudo systemctl enable --now glusterd
```

#### ファイアウォールの設定

各ホスト上で、以下のコマンドを実行してポートを開放します。

```
[全ホスト]$ sudo firewall-cmd --add-service=glusterfs --permanent
[全ホスト]$ sudo firewall-cmd --reload
```

####  プールの構築

どれか1つのノードで、gluster peer probe コマンドを実行し、他のサーバをプールに追加します。

ke2-server1 上で実行する場合：

```
[ke2-server1]$ sudo gluster peer probe ke2-server2
[ke2-server1]$ sudo gluster peer probe ke2-server3
```

プールを構成するサーバの一覧は、以下のコマンドで確認することができます。

```
[ke2-server1]$ sudo gluster pool list
UUID                                    Hostname        State
9d593742-d630-48b0-8570-066d15822c4d    ke2-server2     Connected
9b7f2c39-a0ce-498f-9939-4fcf55a36fac    ke2-server3     Connected
d47ce78a-0ffd-468f-9218-32fa2d97c431    localhost       Connected
```

#### GlusterFS ボリュームの作成

ボリューム gvol0 を作成してスタートします。GlusterFS クラスタ内のどれ
か1つのノード上で（以下の例では ke2-server1 を想定）以下を実行します。
(ここでは root パーティションに作成しているため、force オプションが必
要です)

```
[ke2-server1]$ sudo gluster vol create gvol0 replica 3 ke2-server1:/var/glustervol0 ke2-server2:/var/glustervol0 ke2-server3:/var/glustervol0 force
[ke2-server1]$ sudo gluster vol start gvol0
```

#### ボリュームの マウント

作成した gvol0 ボリュームを各ノード上でマウントします。

```
[全ホスト]$ sudo mkdir /mnt/gluster
[全ホスト]$ sudo mount -t glusterfs localhost:/gvol0 /mnt/gluster
```

再起動時に自動的にマウントされるように以下を /etc/fstab に追加しておき
ます。

```
localhost:/gvol0 /mnt/gluster glusterfs _netdev,defaults 0 0
```

### PostgreSQL/Pgpool-II クラスタの構築

各 Swarm ノード上で実行している Kompira エンジンや Kompira アプリケー
ションサーバのコンテナからアクセス可能なデータベースとして、
PostgreSQL/Pgpool-II クラスタを構築する手順について説明します。

データベースクラスタには最低で 3台 のホストが必要となります。ここでは、
Docker Swarm クラスタのホスト上にデータベースクラスタを同居した形で構
築する想定ですが、Docker Swarm クラスタとは別にデータベースクラスタを
構築しても構いません。

#### PostgreSQL/Pgpool-II のセットアップ

ここでは、本ディレクトリに附属するセットアップ用のスクリプトを用いて構
築する手順を示します。なお、このスクリプトは RHEL 9系 (CentOS Stream 9、
Rocky Linux 9、AlmaLinux 9など互換 OS を含む) のサーバを対象としていま
す。その他の OS 上にセットアップする場合は、スクリプトの手順を参考に構
築してください。

なお、本セットアップスクリプトでは、PostgreSQL/Pgpool-II の各ユーザー
とパスワードをデフォルトで以下のように規定しています。

  ユーザ名/パスワード: 備考
  - kompira/kompira: Kompiraアクセス用のユーザ
  - pgpool/pgpool: Pgpool-IIのレプリケーション遅延チェック(sr_check_user)、ヘルスチェック専用ユーザ(health_check_user)。
  - postgres/postgres: オンラインリカバリの実行ユーザ
  - repl/repl: PostgreSQLのレプリケーション専用ユーザ

(1) 各ホストにスクリプトファイルを転送する

クラスタを構成する各ホストに、本ディレクトリに含まれる以下のスクリプト
を転送します。

  - setup_pgpool.sh
  - setup_pgssh.sh

(2) 各ホストで setup_pgpool.sh を実行する

各ホストで setup_pgpool.sh スクリプトを実行します。このスクリプトでは、
PostgreSQL 16、および、Pgpool-II のインストールと初期設定を行います。
setup_pgpool.sh 起動時に以下の環境変数を指定する必要があります。

  - CLUSTER_VIP: Pgpool-II で使用する仮想IPアドレス
  - CLUSTER_HOSTS: クラスタを構成するホスト名（空白区切り）

CLUSTER_HOSTS の最初のホストがプライマリサーバとして、残りはセカンダリ
サーバとしてセットアップされます。(したがって、各ホスト上で実行する際
に、CLUSTER_HOSTS のホストの順番は同一に与えるように注意してください)

以下に実行例を示します。

```
[全ホスト]$ CLUSTER_VIP=10.20.0.100 CLUSTER_HOSTS='ke2-server1 ke2-server2 ke2-server3' ./setup_pgpool.sh
```

一般ユーザで実行する場合、起動後に sudo のパスワードを入力を求められます。

(3) 各ホストで setup_pgssh.sh を実行する

各ホストで setup_pgssh.sh スクリプトを実行します。このスクリプトでは、
postgres ユーザーの SSH 鍵ファイルを作成し、公開鍵ファイルを各ホストの
./.ssh/authorized_keys に追加して、パスワード無しでログインできるよう
にします。setup_pgssh.sh 起動時に CLUSTER_HOSTS 環境変数を指定する必要が
あります。

以下に実行例を示します。(CLUSTER_HOSTS の順番によって、ノードIDを割り
当てているため、各ホストで同一になるように注意してください)

```
[全ホスト]$ CLUSTER_HOSTS='ke2-server1 ke2-server2 ke2-server3' ./setup_pgssh.sh
```

一般ユーザで実行する場合、起動後に sudo のパスワードを入力、および、実
行ユーザがクラスタを構成する各リモートホストにログインするためのパスワー
ドとリモートホストでの sudo パスワードの入力を求められます。

#### Pgpool-II の起動とリカバリ

次に、Pgpool-II の起動と、PostgreSQL のスタンバイの設定を行います。

(1) Pgpool-II の起動

プライマリサーバ（ここでは ke2-server1 を想定）から順番に各ホスト上で
以下のコマンドを実行し、Pgpool-II を起動します。

```
[全ホスト]$ sudo systemctl start pgpool
```

プライマリサーバでは setup_pgpool.sh の実行によって、既に PostgreSQL
サーバが起動しています。いずれかのホスト上で以下のコマンドを実行して、
PostgreSQLサーバがプライマリモードで動作していることを確認してください。

(2) PostgreSQL スタンバイサーバの作成

Pgpool-IIのオンラインリカバリ機能を利用し、ke2-server2 と ke2-server3
をスタンバイサーバとして構築し、Pgpool-II管理下に追加します

仮想IP経由で Pgpool-II に接続し、バックエンドノードのステータスを確認
します。 下記の結果のように、プライマリサーバが ke2-server1で起動して
おり、ke2-server2 と ke2-server3 は「down」状態になっています

```
[いずれかのサーバ]$ psql -h 10.20.0.100 -p 9999 -U pgpool postgres -c "show pool_nodes"
ユーザー pgpool のパスワード: 
 node_id |   hostname  | port | status | pg_status | lb_weight |  role   | pg_role | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change  
---------+-------------+------+--------+-----------+-----------+---------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | ke2-server1 | 5432 | up     | up        | 0.333333  | primary | primary | 0          | true              | 0                 |                   |                        | 2024-06-11 18:18:20
 1       | ke2-server2 | 5432 | down   | down      | 0.333333  | standby | unknown | 0          | false             | 0                 |                   |                        | 2024-06-11 18:16:06
 2       | ke2-server3 | 5432 | down   | down      | 0.333333  | standby | unknown | 0          | false             | 0                 |                   |                        | 2024-06-11 18:16:06
(3 行)
```

オンラインリカバリ機能を使用するには、pcp_recovery_node コマンドを実行
します。

```
[いずれかのサーバ]$ pcp_recovery_node -h 10.20.0.100 -p 9898 -U pgpool -n 1 -W
Password:
pcp_recovery_node -- Command Successful

[いずれかのサーバ]$ pcp_recovery_node -h 10.20.0.100 -p 9898 -U pgpool -n 2 -W
Password:
pcp_recovery_node -- Command Successful
```

ke2-server2 と ke2-server3 の PostgreSQL がスタンバイとして起動してい
ることを確認します。

```
[いずれかのサーバ]$ psql -h 10.20.0.100 -p 9999 -U pgpool postgres -c "show pool_nodes"
ユーザー pgpool のパスワード: 
 node_id |   hostname  | port | status | pg_status | lb_weight |  role   | pg_role | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change  
---------+-------------+------+--------+-----------+-----------+---------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | ke2-server1 | 5432 | up     | up        | 0.333333  | primary | primary | 0          | false             | 0                 |                   |                        | 2024-06-11 18:18:20
 1       | ke2-server2 | 5432 | up     | up        | 0.333333  | standby | standby | 0          | true              | 0                 | streaming         | async                  | 2024-06-11 18:22:54
 2       | ke2-server3 | 5432 | up     | up        | 0.333333  | standby | standby | 0          | false             | 0                 | streaming         | async                  | 2024-06-11 18:22:54
(3 行)
```

## Kompira Enterpise の開始

クラスタ構成の Kompira Enterpise の開始する前にデプロイの準備を行ないます。

以降の説明はこのディレクトリで作業することを前提としていますので、このディレクトリに移動してください。

    $ cd ke2/cluster/swarm

まず、コンテナイメージの取得と SSL 証明書の生成を行なうために、以下のコマンドを実行します。

    $ docker compose pull
    $ ../../../scripts/create-cert.sh

次に、共有ディレクトリ (SHARED_DIR) にはあらかじめ以下のディレクトリを作成しておく必要があります。

	- ${SHARED_DIR}/
		- log/
		- var/
		- ssl/

SHARED_DIR を `/mnt/gluster` とする場合は、例えば以下のようにディレクトリを作成してください。

	$ mkdir -p /mnt/gluster/{log,var,ssl}

次に、データベース上でのパスワード情報などの暗号化に用いる秘密鍵をファイル `${SHARED_DIR}/var/.secret_key` に準備します。
Kompira 用データベースを新規に構築する場合は、たとえば以下のようにして空のファイルを用意してください。

    $ touch /mnt/gluster/var/.secret_key

※ 外部データベースとして既に構築されている Kompira データベースを用いる場合は、そのデータベースにおける秘密鍵を `${SHARED_DIR}/var/.secret_key` に書き込んでおいてください。

    $ echo -n 'xxxxxxxxxxxxxxxx' > /mnt/gluster/var/.secret_key

次に、Docker Swarm クラスタを構成するいずれかのマネージャノード上で以下のコマンドを実行してください。
このとき少なくとも環境変数 SHARED_DIR で共有ディレクトリを指定してください。

	$ SHARED_DIR=/mnt/gluster ./setup_stack.sh

エラーが無ければ docker-swarm.yml というファイルが作成されているはずです。
これでシステムを開始する準備ができました。以下のコマンドを実行して Kompira Enterprise 開始をします。

	$ docker stack deploy -c docker-swarm.yml ke2

Kompira Enterprise を停止するには以下のコマンドを実行します。

	$ docker stack rm ke2

## カスタマイズ
### 環境変数によるカスタマイズ

setup_stack.sh を実行するときに環境変数を指定することで、簡易的なカスタマイズを行なうことができます。

    $ 環境変数=値... ./setup_stack.sh

| 環境変数           | 備考                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `SHARED_DIR`       | 共有ディレクトリ（各ノードからアクセスできる必要があります）                                |
| `DATABASE_URL`     | 外部データベース                                                                            |
| `KOMPIRA_LOG_DIR`  | ログファイルの出力先ディレクトリ（未指定の場合は `${SHARED_DIR}/log` に出力されます）       |
| `NGINX_PORT_MODE`  | Nginx の公開ポートモード (`host`、`ingress`) の設定（デフォルト: `ingress`） <br />`ingress`: HTTP(S) アクセスはクラスタを構成する各ホスト上の nginx コンテナに負荷分散されます。<br />`host`: HTTP(S) アクセスは URL で指定されたホスト上で動作する nginx コンテナが受信します。|                                                                  

カスタマイズ例: 

    $ DATABASE_URL="pgsql://kompira:kompira@10.20.0.100:9999/kompira" ./setup_stack.sh

### 詳細なカスタマイズ

コンテナ構成などを詳細にカスタマイズしたい場合は、setup_stack.sh スクリプトで生成された docker-swarm.yml ファイルを、目的に合わせてカスタマイズしてください。

## システムの管理

より詳しいシステムの管理手順などについては、「KE 2.0 管理マニュアル」を参照してください。
