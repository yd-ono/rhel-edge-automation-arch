# RHEL for Edge Automation

## はじめに

RHEL for Edge (RFE) は、RHEL の構築とデプロイのための新しいモデルを導入します。このリポジトリには、RFE コンテンツを大規模に構築して提供する GitOps アプローチをサポートするために必要なドキュメントと自動化が含まれています。

## 注目の分野

このリポジトリのデザインは、以下のトピックに焦点を当てます：

* Image Builder（複数）の展開
* ブループリントの定義管理
* RFEイメージの構築
* RFEアーティファクトの管理/ホスティング
  * キックスタート
  * RFE OSTreeコンテンツ
* CI/CD ツール/プロセス
* RFE導入のエンドツーエンドインストール/アップデート
* 規模に応じたRFE導入の管理
  * ロギング/メトリックス収集の集計について
  * コンテナ化されたワークロードのデプロイメント

## アーキテクチャ
![全体アーキテクチャ](/images/overall-architecture.png)

## 上記サイト構成要素

OpenShiftは、上記のサイトコンポーネントをすべてホストするために使用されます。これらのコンポーネントは以下の通りです：

* Helm/Argo CD
  * GitOpsベースのデプロイメントと設定
* OpenShift Virtualization
  * RHEL Image Builder
  * 並列パイプライン（composes）をサポートするために、複数のImage Builder VMを配置することができます。
* OpenShift Pipelines
  * Ansible playbookの実行
* Nexus
  * 
* 一般的なオブジェクトストレージとしてOpenShift Data Foundation（NooBaaのみ）を使用します。
* RFE OSTreeのコンテンツをRed Hat Quayで配信開始

## 上記サイトコンポーネントの配置

[Helm](https://helm.sh)と[Argo CD](https://argoproj.github.io/argo-cd/)は、プロジェクトのコンポーネントをデプロイし管理するために使用します。HelmはArgo CDのapp of appsパターンを動的に生成するために使用され、その結果、ターゲット環境に必要な特定のコンポーネントをデプロイするために必要なすべてのHelmチャートを取り込みます。

始める前に、`oc`/`kubectl`、`git`、`tkn`、`helm`の最新バージョンのクライアントがインストールされていることを確認します。また、SSH キーペアを生成する必要があります (以下に示す `ssh-keygen` を使用した例)。

### ブートストラップ環境

まず、以下のコマンドを実行して、リポジトリをクローンします：

``shell
git clone https://github.com/redhat-cop/rhel-edge-automation-arch.git
```

#### 値ファイルとSSHキーペアの準備

デプロイ時にいくつかのシークレットが作成されます。ブートストラッププロセスの一部として、それらに値を提供する必要があります。特定のコンポーネントの表は、以下にレイアウトされています：

| コンポーネント｜説明
|:-----------------------------|:------------------------------------------------------------------------|
| SSHキー｜イメージビルダーVMへのキーベースの認証をサポートするために使用します。
| Red Hat Portalのユーザー名｜Image Builder VMを購読するためのユーザー名｜Image Builder VMを購読するためのユーザー数
| Red Hat Portalのパスワード｜Image BuilderのVMを登録するためのパスワード｜です。
| プール ID｜Red Hat Subscription Manager のプール ID を使用して、適切なサブスクリプションを Image Builder VM にマップします。
| Red Hat Portal Offline Token｜Red Hat APIへのアクセスやRHELイメージのダウンロードに使用されるトークンです｜。

SSHキーペアを生成するには、以下のコマンドを実行します：

``shell
ssh-keygen -t rsa -b 4096 -C cloud-user@image-builder -f ~/.ssh/image-builder
```

リポジトリのルートから、先ほど作成したキーペアへのシンボリックリンクを作成します：

``shell
ln -s ~/.ssh/image-builder charts/bootstrap/files/ssh/image-builder-ssh-private-key
ln -s ~/.ssh/image-builder.pub charts/bootstrap/files/ssh/image-builder-ssh-public-key
```

残りの値は、Helmの値ファイルで定義します。リポジトリのルートに `examples/values/local/bootstrap.yaml` というファイルを作成し、以下を追加します：

``yaml
RHSM
  ポータルになります：
    secretName: redhat-portal-credentials（レッドハットポータルクレデンシャル）。
    offlineToken: "Opij2qw3eCf890ujjwec8j..."
    パスワード："changeme"
    poolId： "ssa77eke7ahs0123djsdf92340p9okjd"
    ユーザー名："alice"
```

offlineToken`、`poolId`、`username`、`password`の値は、必ず自分のアカウントの詳細と一致するように変更してください。Red Hat API のオフライントークンの生成方法がわからない場合は、[こちら](https://access.redhat.com/articles/3626371#bgenerating-a-new-offline-tokenb-3) にドキュメントがあります。

#### OpenShift GitOps OperatorとArgo CDのデプロイ

SSHキーペアと値ファイルが揃ったら、デプロイを開始します。以下のスクリプトを実行し、OpenShift GitOps OperatorとArgo CDをインストールします。

``shell
./setup/init.sh
```


### デプロイメント

空のOpenShiftクラスタに参照環境をデプロイするには、以下のコマンドを実行します：

``shell
helm upgrade -i -n rfe-gitops bootstrap charts/bootstrap/ -f examples/values/local/bootstrap.yaml -f examples/values/deployment/default.yaml
```

デフォルトのインストールでは、クラスタ上のすべての管理対象コンポーネントの展開と構成が行われます。HTPasswdのID

www.DeepL.com/Translator（無料版）で翻訳しました。