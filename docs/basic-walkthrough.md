# Basic Walkthrough

このドキュメントは、最初の RHEL for Edge イメージを構築するプロセスについて説明します。

## 事前準備

開始する前に、以下の要件を満たしている必要があります。

1. OpenShift CLI ツール
2. Tekton CLIツール
3. curl CLIツール
4. 本リポジトリに関連するツールでプロビジョニングされたOpenShiftクラスタ
5. `cluster-admin`権限を持つユーザーとして、OpenShiftクラスタにアクセスする。

## ユースケース概要

このウォークスルーでは、RHEL for Edge コンテンツの構築、公開、消費の容易さを説明します。サンプルのユースケースでは、コンテナで動作する [IBM Developer Model Asset Exchange: Weather Forecaster](https://github.com/IBM/MAX-Weather-Forecaster) アプリケーションを持つエッジノードを構築し、デプロイします。このプロセスは以下のように構成されています。

* 以下のような一連のパイプラインを実行します。
  + Image Builderを使用して、compose image type `rhel-edge-container` を使用し、カスタム RHEL for Edge イメージ (OSTree commit) を作成する。
  + 生成されたOCIコンテナをQuayへPushする
  + OpenShiftにOCIコンテナをデプロイしてステージングする。
  + OpenShift上で動作するWebサーバーからOStreeのコンテンツを同期して本番環境へ配信する。
* コンテナワークロードを実行するための設定を含むキックスタートファイルを作成する。
* OSTree コミットとキックスタートを組み込んだ自動起動の RHEL for Edge インストーラ ISO を作成する。

## RHEL for Edgeイメージのビルド

RHEL for Edgeイメージの構築プロセスでは、パッケージのリスト、パッケージのエントリモジュール、および結果のイメージに対するカスタマイズを含むブループリントを構成します。このアーキテクチャには、既存のブループリントからRHEL for Edgeイメージを構築することを目的としたTektonパイプラインが含まれています。ブループリントのサンプルは、このリポジトリの [blueprints](https://github.com/yd-ono/rhel-edge-automation-arch/tree/blueprints) ブランチにあります。

最も基本的な構成については、サンプル [hello-world](https://github.com/yd-ono/rhel-edge-automation-arch/tree/blueprints/hello-world) ブループリントが用意されており、コンテナ化されたアプリケーションを実行するために必要な構成が提供されます。

RHEL for Edgeアプリケーションを管理するためのコンテンツは、すべてOpenShiftクラスタ内の`rfe` namespaceにあります。

OpenShift CLIにログインして、`rfe` namespaceに変更します。


```shell
oc project rfe
```

rfe-oci-image-pipeline` Tektonパイプラインは、新しいRHEL for Edgeイメージを構築し、得られたOCIコンテナをQuayのOSTree Commitで保存する役割を担っています。

プロジェクトのルートから、以下のコマンドを実行して `rfe-oci-image-pipeline` パイプラインを実行し、 `hello-world` ブループリントをビルドします。


```shell
oc adm policy add-scc-to-user pipelines-scc -z rfe-automation

tkn pipeline start rfe-oci-image-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p blueprint-dir=hello-world 
```

コマンドの意味は以下のとおりです。

* `tkn` - Tekton CLI
* `pipeline` - 管理するリソース。
* `start` - 実行するアクション。パイプラインの実行を開始します。
* `--workspace name` - ファイル [examples/pipelines/volumeclaimtemplate.yaml](https://github.com/yd-ono/rhel-edge-automation-arch/blob/main/examples/pipelines/volumeclaimtemplate.yaml) にあるテンプレートを使用して Tekton ワークスペースをバックアップするために PersistentVolumeClaim を使用することを指定する。
* `-s rfe-automation` - パイプラインを実行するために使用するサービスアカウント名です。
* `--use-param-default` - 明示的に指定しない限り、パイプラインのデフォルトパラメータが適用されます。
* `-p blueprint-dir=hello-world` - クローンリポジトリのブループリント・ファイルを含むディレクトリです。デフォルトでは、このリポジトリの _blueprints_ ブランチが使用されます。


コマンドの出力には、ビルドの進捗状況を確認するためのコマンドが用意されています。

_Note: RHEL for Edgeイメージの構築プロセスには時間がかかります！_

なお、Quayへのイメージのpushの際に、「connection reset by peer」によりリトライが継続することがあります。
その際は、ローカルPCの環境などから以下のコマンドでQuayへコンテナイメージをpushできるか確認してみてください。

```
oc get secret publisher -n rfe -ojsonpath='{.data.\.dockerconfigjson}' | base64 -d
{
    "auths": {
        "quay-quay-quay.apps....": {
            "auth": "cmZlK..."
        }
    }
}
export QUAY_USER=$(echo cmZlK... | base64 -d | awk -F":" '{print $1}')
export QUAY_PASSWORD=$(echo cmZlK... | base64 -d | awk -F":" '{print $2}')
podman login --tls-verify=false $(oc get route quay-quay -n quay -ojsonpath='{.spec.host}') \
--username $QUAY_USER --password $QUAY_PASSWORD

podman push registry.access.redhat.com/ubi9/ubi:latest \
$(oc get route quay-quay -n quay -ojsonpath='{.spec.host}')/rfe/hello-world:9.0.0 \
--tls-verify=false \
--remove-signatures
```



### パイプラインの結果

各パイプラインの実行は、3つの結果を返します。

* `build-commit` - Image Builder からのビルドコミット ID。
* `image-path` - OCI コンテナの Quay レジストリ内の位置
* `image-tags` - コンテナに適用されるタグ（JSONリスト）。

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
export IMAGE_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-image-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

oc get pipelinerun -n rfe $IMAGE_PIPELINE -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "build-commit",
    "value": "ab07f144-43a7-49b3-93de-99e1562435f9"
  },
  {
    "name": "image-path",
    "value": "quay-quay-quay.apps.cluster.com/rfe/hello-world"
  },
  {
    "name": "image-tags",
    "value": "[\"latest\", \"0.0.1\"]"
  }
]
```

### 確認

パイプラインが完了すると、Image Builder で生成された OCI コンテナが Quay に格納されているはずです。確認のため、以下のコマンドを実行してQuayへの経路を取得します。

```shell
oc get quayregistry quay -n quay -ojsonpath='{.status.registryEndpoint}'
```

Quayは外部認証を使用するように設定されていないので、ユーザー名は実行することで見つけることができます。

```shell
oc get secret quay-rfe-setup -n rfe -o go-template='{{ .data.username | base64decode }}'
```
そして、実行によるパスワード。

```shell
oc get secret quay-rfe-setup -n rfe -o go-template='{{ .data.password | base64decode }}'
```

Quayにログインしたら、ページの右側にある_Users and Organizations_のRFE organizationをクリックし、ブループリントに関連するリポジトリ名を選択します。

画面の左側にある_Tags_アイコンをクリックすると、関連するタグが表示されます。パイプラインの実行ごとに、2 つのタグが作成されます。

* 最も新しいイメージを指す _latest_ タグ。
最新のイメージを指す _latest_ タグ * ブループリントで指定されたバージョンを示すタグ

この時点で、RFE コンテンツのデプロイで使用するコンテナを手動でプル/デプロイすることができます。


## OSTreeコミットしたOCIコンテナをステージングへ移行

QuayでOSTreeコミットしたOCIコンテナができたので、パイプラインを実行してOpenShiftのステージング環境としてデプロイしてみましょう。

プロジェクトのルートから、以下のコマンドを実行して `rfe-oci-stage-pipeline` パイプラインを実行し、前回のパイプライン (`rfe-oci-image-pipeline`) 実行で構築したOCIコンテナをデプロイします。

```shell
tkn pipeline start rfe-oci-stage-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/hello-world \
-p image-tag=latest
```

このコマンドは、前のパイプラインの実行と似ていますが、以下のパラメータが使用されます。

* `-p image-path=quay-quay.apps.cluster.com/rfe/hello-world` - Quayレジストリに格納されているOCIコンテナのパスです。
* `-p image-tag=latest` - _latest_ というタグのついたイメージを使用します。

### パイプラインの結果


各パイプラインの実行は、1つの結果を返します。

* `content-path` - OSTreeのリポジトリへのパスです。

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
export STAGE_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-stage-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

oc get pipelinerun -n rfe $STAGE_PIPELINE -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "content-path",
    "value": "http://hello-world-latest-rfe.apps.demo.sandbox2633.opentlc.com/repo"
  }
]
```

### 確認

パイプラインが実行されると、ImageStream、Deployment、Service、Routeが`rfe`名前空間に設定されます。デプロイメントを確認するために、OSTree Commit のハッシュをクエリしてみます。先ほどの `rfe-oci-stage-pipeline` パイプラインの実行で得られた `content-path` の結果を使用して `curl` を実行し、`/refs/heads/rhel/8/x86_64/edge` を追記します。例えば、以下のようになります。

```
$ curl http://hello-world-latest-rfe.apps.demo.sandbox2633.opentlc.com/repo/refs/heads/rhel/8/x86_64/edge
3e0a552e018828c3cdbe5f32b56fa6a4b7a2956e6eb8da3f5b24eb5d91114bf5
```

## ステージングから本番環境へ移行

次に、ステージング環境から本番環境へOSTree Commitを同期させることになります。

プロジェクトのルートから、以下のコマンドを実行し、`rfe-oci-publish-content-pipeline`パイプラインを実行します。

```shell
tkn pipeline start rfe-oci-publish-content-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/hello-world \
-p image-tag=latest 
```

このコマンドは、前のパイプラインの実行と似ていますが、以下のパラメータが使用されます。

* `-p image-path` - Quayレジストリに格納されているOCIコンテナのパスです。
* `-p image-tag` - _latest_ というタグのついたイメージを使用します。

### パイプライン結果

各パイプラインの実行は、1つの結果を返します。

* `content-path` - OSTreeリポジトリへのパス。

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
export PUBLISH_CONTENT_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-publish-content-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

oc get pipelinerun -n rfe $PUBLISH_CONTENT_PIPELINE -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "content-path",
    "value": "http://httpd-rfe.apps.demo.sandbox132.opentlc.com/hello-world/latest"
  }
]
```

### 確認

パイプラインが実行されると、OSTree Commitは本番のWebサーバーに同期されます。以下のコマンドを実行して、ハッシュを確認します。

前の `rfe-oci-publish-content-pipeline` パイプラインの実行で得られた `content-path` の結果を使用して `curl` を実行し、 `/refs/heads/rhel/8/x86_64/edge` を追記します。例えば、以下のような感じです。

```shell
export OSTREE_REPO_URL=$(oc get pipelinerun -n rfe $PUBLISH_CONTENT_PIPELINE -ojsonpath='{.status.pipelineResults[*].value}')
curl $OSTREE_REPO_URL/refs/heads/rhel/8/x86_64/edge
3e0a552e018828c3cdbe5f32b56fa6a4b7a2956e6eb8da3f5b24eb5d91114bf5
```

このリポジトリのハッシュは、`rfe-oci-stage-pipeline`パイプラインの実行中に生成されたリポジトリのハッシュと一致するようになりました。

## キックスタートファイルを生成

`rfe-kickstart-pipeline`というTektonパイプラインは、NexusとHTTPDサーバーの両方にKickstartファイルを発行する役割を担います。パイプラインはAnsibleを使用し、Jinjaベースのテンプレートがキーバリュー（特にOSTreeリポジトリの場所）を注入するために利用できます。

`rfe-oci-stage-pipeline`または`rfe-oci-publish-content-pipeline`のいずれかのパイプラインの結果からOSTreeリポジトリの場所を使用して、次のコマンドを実行します。

```shell
export PUBLISH_CONTENT_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-publish-content-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')
export OSTREE_REPO_URL=$(oc get pipelinerun -n rfe $PUBLISH_CONTENT_PIPELINE -ojsonpath='{.status.pipelineResults[*].value}')

tkn pipeline start rfe-kickstart-pipeline \
-s rfe-automation \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
--use-param-defaults \
-p kickstart-path=ibm-weather-forecaster/kickstart.ks \
-p ostree-repo-url=$OSTREE_REPO_URL
```

このコマンドは、前のパイプラインの実行と似ていますが、次のパラメータが使用されます。

前のコマンドを分解すると

* `-p kickstart-path` - 参照されるリポジトリで使用するキックスタートの場所です。デフォルトでは、このリポジトリの _kickstarts_ ブランチが使用されます。
* `-p ostree-repo-url` - OSTree リポジトリの場所です。

tkn pipeline` コマンドの出力は、ビルドの進捗を見るための別のコマンドを提供します。

### パイプライン結果

各パイプラインの実行は、2つの結果を返します。

* `Artifact-repository-storage-url` - Nexus サーバー上のキックスタートの位置。
* `serving-storage-url` - HTTPD サーバー上のキックスタートの場所。

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
export KICKSTART_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-kickstart-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

oc get pipelinerun $KICKSTART_PIPELINE -ojsonpath='{.status.pipelineResults}'
[{"name":"artifact-repository-storage-url","value":"https://nexus-rfe.apps.demo.sandbox2633.opentlc.com/repository/rfe-kickstarts/ibm-weather-forecaster/kickstart.ks"},{"name":"serving-storage-url","value":"http://httpd-rfe.apps.demo.sandbox2633.opentlc.com/kickstarts/ibm-weather-forecaster/kickstart.ks"}]
```

### 確認

検証するには、`artifact-repository-storage-url` と `serving-storage-url` パイプラインの結果で定義された URL を使用してキックスタートファイルを引き出すだけです。

## 自動ブート用RHEL for Edgeイメージ(ISO)を生成

Image Builderの機能のひとつに、インストーラに OSTree コミットを埋め込んだインストールメディアを構成する機能 (`image-type` `rhel-edge-installer` を使用) があります。このプロジェクトのパイプラインはさらに一歩進んで、生成された ISO にキックスタートファイルを埋め込み、埋め込まれたキックスタートを使用して RFE を自動的にインストールするように `EFI/BOOT/grub.cfg`、`isolinux/isolinux.cfg` を設定し直します。

プロジェクトのルートから、以下のコマンドを実行して `rfe-oci-iso-pipeline` パイプラインを実行します。

```shell

export KICKSTART_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-kickstart-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

export PUBLISH_CONTENT_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-publish-content-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

tkn pipeline start rfe-oci-iso-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p kickstart-url=$(oc get pipelinerun -n rfe $KICKSTART_PIPELINE -ojsonpath="{.status.pipelineResults[1].value}") \
-p ostree-repo-url=$(oc get pipelinerun -n rfe $PUBLISH_CONTENT_PIPELINE -ojsonpath='{.status.pipelineResults[*].value}')
```

このコマンドは、前のパイプラインの実行と似ていますが、次のパラメータが使用されます。

* `-p kickstart-url` - ISO に埋め込まれるキックスタートへのパス。
* `-p ostree-repo-url` - ISO に埋め込まれる OSTree リポジトリへのパスです。

### 独自のキックスタートファイルを使用する場合

独自のキックスタートファイルを用意する場合は、`ostreesetup`コマンドの以下の行を使用します（`--url`はインストーラに組み込まれているOSTreeリポジトリを指していますが、任意のOSTreeリポジトリを指すことができることに注意してください）。

```shell
ostreesetup --nogpg --url=file:///ostree/repo/ --osname=rhel --remote=edge --ref=rhel/8/x86_64/edge
```

従来のRHELのインストールと同様に、AnacondaはRHEL for Edgeのインストールに使用されます。ただし、すべてのAnacondaモジュールが有効になっているわけではありません。利用可能なモジュールは以下の通りです。

* org.fedoraproject.Anaconda.Modules.Network
* org.fedoraproject.Anaconda.Modules.Payloads
* org.fedoraproject.Anaconda.Modules.Storage を参照してください。

キックスタートによるユーザー作成などの一般的なタスクは機能しません。これらのアクションは、OSTree のコミットを構築するために使用するブループリント ファイルに含める必要があります。しかし、`%post` のような他のタスクはまだ動作するはずです。

### パイプラインの結果

各パイプラインの実行は、2つの結果を返します。

* `iso-url` - オートブートするISOの場所

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
export ISO_PIPELINE=$(tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-iso-pipeline --limit 1 -ojsonpath='{.items[*].metadata.name}')

oc get pipelinerun -n rfe $ISO_PIPELINE -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "iso-url",
    "value": "http://httpd-rfe.apps.demo.sandbox725.opentlc.com/46014545-0974-4295-b794-c6fb1cc5a347-auto.iso"
  }
]
```

### 検証

`iso-url`パイプラインの結果として出力されたURLへアクセスするとISOをダウンロードできます。
自動ブート用ISOは、RHEL for Edgeを自動的にインストールするように構成されており、ユーザーの入力は必要ありません。ISOを起動するだけで、インストールできます。

```
wget http://httpd-rfe.apps.demo.sandbox725.opentlc.com/46014545-0974-4295-b794-c6fb1cc5a347-auto.iso
```

![Tekton Pipelineの状態](/images/tekton.png)

### VirtualBoxで仮想マシンを作成

### 仮想マシンを新規作成します
![仮想マシン作成](/images/vmcreate.png)

CPUコア、メモリ、DISKサイズは任意の値を指定してください。

### EFIを有効化します
![EFI有効化](/images/iso.png)

### 作成したISOファイルを指定します
![ISO指定](/images/iso.png)

### 仮想マシンを起動すると自動インストールが開始します
![Kickstartの様子](/images/kickstart.gif)

### アプリケーションの確認

マシンが再起動したら、ノードのインストールの一部として作成されたユーザーでログインします。
ログインしたら、アプリケーションコンテナが起動していることを確認します。

```shell
sudo podman ps
```

`localhost:5000`へHTTPアクセスするとサンプルアプリのHTMLがレスポンスします。

```shell
curl localhost:5000
```

参考. サンプルアプリは天気予報APIのSwaggerの画面です。

![サンプルアプリ](/images/app.png)

## TIPS. rootパスワードを忘れた際の対応
### ブートメニューで`e`を押下
### `linux`の行で`rd.break enforcing=0`を入力
### ファイルシステムをrwへ変更

```
# mount –o remount,rw /sysroot
```
### パスワード変更
```
# chroot /sysroot
# passwd
# exit
```

