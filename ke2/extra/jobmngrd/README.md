# Kompira Enterprise 2.0: 外部 jobmngrd 構成

KE2.0 の外部に jobmngrd だけを配置する構成の Docker Compose ファイルが含まれています。

## KE2.0 側での準備

事前に KE2.0 システム側で、AMQPS 接続を許可するファイヤーウォールの設定と、rabbitmq に外部接続用のユーザの追加とパーミッションの設定が必要になります。

まず OS ごとの手順で AMQPS (5671番ポート) の許可設定を行なってください。firewall-cmd を使う場合の例は以下のようになります。KE2.0 がクラスタ構成の場合は全てのノードで許可設定を行なってください。

    $ sudo firewall-cmd --add-service=amqps --permanent
    $ sudo firewall-cmd --reload

続けて rabbitmq に外部 jobmngrd から接続するためのユーザーを追加し、パーミッションを設定してください。
ユーザ名 `kompira` / パスワード `kompira` で設定する場合の例を以下に示します。

    $ docker exec $(docker ps -q -f name=rabbitmq) rabbitmqctl add_user kompira kompira
    $ docker exec $(docker ps -q -f name=rabbitmq) rabbitmqctl set_permissions --vhost / kompira '.*' '.*' '.*'

## 外部 jobmngrd の起動

以降の説明はこのディレクトリで作業することを前提としていますので、このディレクトリに移動してください。

    $ cd ke2/extra/jobmngrd

まず、KE2.0 が動作しているシステムの rabbitmq に接続するための `AMQP_URL` を、以下の内容で `.env` ファイルに記述します。ユーザ名・パスワードは上で rabbitmq に追加した値を指定してください。

    AMQP_URL=amqps://<AMQP_USER>:<AMQP_PASSWORD>@<RABBITMQ_HOST>:5671

この構成では `AMQP_URL` の指定が **必須** で、`up` だけでなく `pull` を含むすべての docker compose コマンドで必要です (未指定の場合はいずれのコマンドも即エラー停止します)。`.env` に記述しておくと、このディレクトリで実行する docker compose コマンドすべてに適用されるため、コマンドごとに指定する必要がなくなります。パスワードを平文で含むため、`chmod 600 .env` などでパーミッションを制限してください。`.env` の書式や注意点については [Environment.md](../../../Environment.md) の「環境変数の指定方法」を参照してください。

次に、コンテナイメージの取得を行なうために、以下のコマンドを実行します。

    $ docker compose pull

続けて、以下のコマンドを実行して外部 jobmngrd を開始をします。

    $ docker compose up -d

ブラウザで KE2.0 の「管理領域設定 > デフォルト」 (/config/realms/default) を確認して、「ジョブマネージャ状態」一覧にこのホストがステータス「動作中」として表示されていれば、外部 jobmngrd 構成のセットアップは成功です。

### 参考: `.env` を使わない場合

`.env` を用意せずに、コマンドごとに `AMQP_URL` を指定することもできます。この場合は `up` だけでなく、`pull` など他の docker compose コマンドを実行するときにも毎回指定する必要があります。

    $ AMQP_URL='amqps://<AMQP_USER>:<AMQP_PASSWORD>@<RABBITMQ_HOST>:5671' docker compose pull
    $ AMQP_URL='amqps://<AMQP_USER>:<AMQP_PASSWORD>@<RABBITMQ_HOST>:5671' docker compose up -d
