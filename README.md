# RHEL for Edge Image Build as a Service

## はじめに

本リポジトリは、エッジコンピューティングへインストールするRHEL for EdgeのOSイメージのビルドとキックスタートの組み込みを自動化するデモです。本デモの出力として、HTTPDサーバにキックスタートファイルの組み込まれたOSイメージ(.iso)が格納されます。そのHTTPDサーバのURLをインストールソースとしてネットワークブートすることで、エッジデバイスへのOSのデプロイメントと構築作業を自動化します。

## アーキテクチャ
![全体アーキテクチャ](/images/overall-architecture.png)

## コンポーネント

* Helm/Argo CD
  * GitOpsベースのデプロイメントと設定
* OpenShift Virtualization
  * RHEL Image Builder
  * パラレルなパイプライン（composes）をサポートするために、複数のImage Builder VMを配置することができます。
* OpenShift Pipelines
  * Ansible playbookの実行
* Nexus
  * アーティファクトの管理
* OpenShift Data Foundation
  *  オブジェクトストレージ(Quayで使用)
* Red Hat Quay
  * RHEL for EdgeのOSTreeのコンテンツをホスト

## 動作確認済みの環境

* AWS
* OpenShift 4.12(IPIインストール)

## 環境構築
### 本リポジトリをローカルへclone

```shell
git clone https://github.com/yd-ono/rhel-edge-automation-arch.git
```

### SSHキーペアとRed Hatポータルの認証情報の設定

| コンポーネント | 説明 | Right-aligned |
| :---         | :---         |
| SSHキー   | Image Builder VMへSSHするために使用   |
| Red Hat Portalのユーザー名     | Image Builder VMをサブスクリプションへ登録するためのユーザー名     |
| Red Hat Portalのパスワード   | Image Builder VMをサブスクリプションへ登録するためのパスワード  |
| Pool ID     | Red Hat Subscription Manager のPool ID を使用し、適切なサブスクリプションを Image Builder VM にマップ    |
| Red Hat Portal Offline Token     | Red Hat APIへのアクセスやRHELイメージのダウンロードに使用されるトークン     |

SSHキーペアを生成するには、以下のコマンドを実行します。

```shell
ssh-keygen -t rsa -b 4096 -C cloud-user@image-builder -f ~/.ssh/image-builder
```

リポジトリのルートから、先ほど作成したキーペアへのシンボリックリンクを作成します。

```shell
ln -s ~/.ssh/image-builder charts/bootstrap/files/ssh/image-builder-ssh-private-key
ln -s ~/.ssh/image-builder.pub charts/bootstrap/files/ssh/image-builder-ssh-public-key
```

残りの値は、Helmの値ファイルで定義します。リポジトリのルートに `examples/values/local/bootstrap.yaml` というファイルを作成し、以下を追加します。

```yaml
rhsm:
  portal:
    secretName: redhat-portal-credentials
    offlineToken: "Opij2qw3eCf890ujjwec8j..."
    password: "changeme"
    poolId: "ssa77eke7ahs0123djsdf92340p9okjd"
    username: "alice"
```

`offlineToken`、`poolId`、`username`、`password`の値は、必ず自分のアカウントの詳細と一致するように変更してください。Red Hat API のオフライントークンの生成方法がわからない場合は、[こちら](https://access.redhat.com/articles/3626371#bgenerating-a-new-offline-tokenb-3) にドキュメントがあります。

#### AWSのベアメタルインスタンスを追加
Workerノードとして、AWSのベアメタルインスタンスを追加します。

```shell
oc apply -f machine-bm.yaml
```

#### OpenShift GitOps Operatorのデプロイ

以下のスクリプトを実行し、OpenShift GitOps Operatorをインストールします。

```shell
./setup/init.sh
```

### デプロイメント

ArgoCDが`chart`ディレクトリ配下の各Helmチャートを参照するように更新します。

```shell
helm upgrade -i -n rfe-gitops bootstrap charts/bootstrap/ -f examples/values/local/bootstrap.yaml -f examples/values/deployment/default.yaml
```

デフォルトのインストールでは、クラスタ上のすべての管理対象コンポーネントのデプロイと構成が行われます。
HTPasswdのIDプロバイダは、パスワードに`openshift`を指定した5人のユーザー（user{1-5}）に対して設定されます。

Argo CD のダッシュボードでデプロイの進捗を確認することができます。URL を取得するには、以下のコマンドを実行します。

```shell
oc get route argocd-server -n rfe-gitops -ojsonpath='https://{.spec.host}'
```

ArgoCDの状態を確認し、SYNC STATUSが`Synced`、HEALTH STATUSが`Healthy`であれば正常にデプロイできています。

```shell
$ oc get application rfe-automation -n rfe-gitops
NAME             SYNC STATUS   HEALTH STATUS
rfe-automation   Synced        Healthy
```

```
注. タイミングの問題でQuayが正常にデプロイできない可能性があります。その際は、一度OpenShift Data FoundationのOperatorを削除し、ArgoCDで再度Syncしてみてください。
```

### Tekton Configを変更
`rfe-oci-push-image` Taskのpipeline.resultのタイプを`array`としているため、Tektonの`enable-api-fields`を`alpha`へ変更してください。

```shell
oc edit tektonconfig
...
    enable-api-fields: alpha
...
```

## Basic Walkthrough
RHEL for Edgeのコンテンツを構築し、それを使ってRHEL for Edgeのインスタンスを作成するまでのエンドツーエンドの流れを示す基本的なウォークスルーは、以下のとおりです。

* [Basic Walkthrough](./docs/basic-walkthrough.md)

## Basic Walkthrough
追加のImage Builderコンテンツソースを使用するMicroShiftイメージの構築のより高度な例は、ここで見つけることができます。

* [MicroShift](./docs/microshift.md)