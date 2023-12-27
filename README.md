# Kompira Enterprise: シンプルで軽量な次世代運用自動化プラットフォーム

## 1. Kompira Enterprise とは

Kompira Enterprise は IT 運用管理業務の自動化を支援するための基盤システムです。
ジョブフローを記述することで、様々な運用業務、管理業務、さらには障害の復旧処理まで自動化することができます。

## 2. Kompira Enteprise Docker Compose ファイル

このリポジトリには、以下の各種デプロイの構成に対応した Kompira Enterprise の **Docker Compose ファイル** が含まれています。

* [オンプレシングル (all in one)][allinone]
* [オンプレシングル (DB外部接続)][withoutdb]
* [Azure Container Instances デプロイ][azureaci]

[allinone]: https://github.com/fixpoint/ke-docker/allinone
[withoutdb]: https://github.com/fixpoint/ke-docker/withoutdb
[azureaci]: https://github.com/fixpoint/ke-docker/azureaci

## 3. クイックスタート

Docker と git コマンドがインストールされているサーバ上で、以下のコマンドを実行することで、すぐに使い始めることができます。

$ git clone https://github.com/fixpoint/ke-docker.git
$ cd ke-docker/allinone
$ docker compose pull
$ docker compose up -d

ブラウザから Docker コンテナが動作しているサーバにアクセス (https://<サーバのアドレス>/.login) するとログイン画面が表示されるので、以下のアカウントでログインすることで Kompira をはじめることができます。

* ユーザ名: `root`
* パスワード: `root`

ログイン後の画面の右上にある「ヘルプ」をクリックすると、オンラインマニュアルが表示されますので使い方の参考にしてください。

## 4. Kompira ライセンス

[Kompira Enterprise ライセンス利用規約](https://www.kompira.jp/Kompira_terms.pdf)に同意の上、ダウンロードページからダウンロードして下さい。

Kompira の使用には、ライセンス登録が必要です。詳しくは [license@kompira.jp](mailto:license@kompira.jp) までご連絡ください。

※ ご利用の Kompira のバージョンに依らず、最新のライセンス利用規約が適用されます。

## 5. Kompira 関連の情報

### 5.1. Kompira 運用自動化コラム

Kompira の実践的な使い方やジョブフローの書き方については [運用自動化コラム](https://www.kompira.jp/column/) を参考にしてみてください。

### 5.2. Kompira コミュニティサイト

Kompira の使い方が分からない場合などは、 [コミュニティ> KompiraEnterprise関連](https://kompira.zendesk.com/hc/ja/community/topics/360000014321-KompiraEnterprise%E9%96%A2%E9%80%A3) を参考にしてみてください。同じような質問や回答が見つからない場合は、新たに投稿してみてください。