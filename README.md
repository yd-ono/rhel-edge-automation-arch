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
  * 
* 一般的なオブジェクトストレージとしてOpenShift Data Foundation（NooBaaのみ）を使用します。
* RFE OSTreeのコンテンツをRed Hat Quayで配信開始

## 動作確認済みの環境

* AWS
* OpenShift 4.12(IPIインストール)

## 環境構築
### 本リポジトリをローカルへclone

```shell
git clone https://github.com/yd-ono/rhel-edge-automation-arch.git
```

### SSHキーペアとRed Hatポータルの認証情報の設定

| コンポーネント｜説明 | 
|:-----------------------------|:------------------------------------------------------------------------|
| SSHキー｜Image Builder VMへのキーベースの認証をサポートするために使用します。 |
| Red Hat Portalのユーザー名｜Image Builder VMを購読するためのユーザー名｜Image Builder VMを購読するためのユーザー数 |
| Red Hat Portalのパスワード｜Image BuilderのVMを登録するためのパスワードです。|
| プール ID｜Red Hat Subscription Manager のプール ID を使用して、適切なサブスクリプションを Image Builder VM にマップします。|
| Red Hat Portal Offline Token｜Red Hat APIへのアクセスやRHELイメージのダウンロードに使用されるトークンです。｜

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

デフォルトのインストールでは、クラスタ上のすべての管理対象コンポーネントのデプロイと構成が行われます。HTPasswdのIDプロバイダは、パスワードに`openshift`を指定した5人のユーザー（user{1-5}）に対して設定されます。

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

## デプロイメントをカスタマイズする
プロジェクトのすべてのコンポーネントのデプロイと管理には、HelmとArgo CDが使用されます。高いレベルでは、アプリケーションマネージャと呼ばれる Helm チャートが、Argo CD のアプリパターンのネストしたアプリを動的に構築するために使用されます。Argo CD の各アプリケーションは、特定のプロジェクトコンポーネントをインストールおよび設定する Helm チャートへのポインタです。デプロイのブートストラップ時に、Helm値ファイルを使用して、どのコンポーネントをデプロイすべきか、どのように設定すべきかをアプリケーションマネージャに伝えます。このパターンを使用することで、特定の環境に合わせたデプロイメントを行う際に、かなりの柔軟性を得ることができます。

## コンポーネントの無効化
特定のコンポーネントのデプロイ/管理を無効にしたい場合（たとえば、ODFがすでにインストールされている独自のクラスタを持ち込む場合など）、チャートの値ファイルにdisable: trueを設定します。例えば、ODFを無効にするには、examples/values/local/disable-odf.yamlに以下のファイルを作成します。

```yaml
# Dynamically Generated Charts
application-manager:
  charts:
    # Top Level RFE App of App Chart
    rfe-automation:
      values:
        charts:
          # Cluster Configuration App of App Chart
          cluster-configs:
            values:
              charts:
                # OpenShift Data Foundations
                odf:
                  disabled: true
 
                 # Operators App of App Chart
                operators:
                  values:
                    charts:
                      odf-operator:
                        disabled: true
```

プロジェクトをデプロイする際に、この値ファイルをhelmに渡します。例えば、以下のような感じです。

```shell
helm upgrade -i -n rfe-gitops bootstrap charts/bootstrap/ -f examples/values/local/bootstrap.yaml -f examples/values/deployment/default.yaml -f examples/values/local/disable-odf.yaml
```

### コンポーネントのカスタマイズ
charts/ディレクトリの各チャートには、デフォルト値ファイルがあります。これらの値は、上記の「コンポーネントを無効にする」で示したのと同じパターンで上書きすることができます。

たとえば、OpenShift Virtualizationのプロセッサエミュレーションを有効にするには、チャートの値ファイルにuseEmulation: trueを設定します。次のファイルを examples/values/local/cnv-processor-emulation.yaml に保存します。

```yaml
---
# Dynamically Generated Charts
application-manager:
  charts:
    # Top Level RFE App of App Chart
    rfe-automation:
      values:
        charts:
          # Cluster Configuration App of App Chart
          cluster-configs:
            values:
              charts:
                # OpenShift Virtualization
                cnv:
                  values:
                    cnv:
                      debug:
                        useEmulation: "true"
```

プロジェクトをデプロイする際に、この値ファイルをhelmに渡します。例えば、以下のような感じです。

```shell
helm upgrade -i -n rfe-gitops bootstrap charts/bootstrap/ -f examples/values/local/bootstrap.yaml -f examples/values/deployment/default.yaml -f examples/values/local/cnv-processor-emulation.yaml
```

## Basic Walkthrough
RHEL for Edgeのコンテンツを構築し、それを使ってRHEL for Edgeのインスタンスを作成するまでのエンドツーエンドの流れを示す基本的なウォークスルーは、以下のとおりです。

* [Basic Walkthrough](./docs/basic-walkthrough.md)

## Basic Walkthrough
追加のImage Builderコンテンツソースを使用するMicroShiftイメージの構築のより高度な例は、ここで見つけることができます。

* [MicroShift](./docs/microshift.md)