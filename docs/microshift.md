# MicroShiftをインストールする

本ドキュメントの前に、[Basic Walkthrough](/docs/basic-walkthrough.md) を実行して、RFE イメージの構築の流れに慣れておくとよいでしょう。

## 事前準備

以下の要件を満たしている必要があります。

1. OpenShift CLI ツール
2. Tekton CLIツール
3. curl CLIツール
4. jq CLIツール
5. 本リポジトリで関連するツールでプロビジョニングされたOpenShiftクラスタ
6. `cluster-admin`権限を持つユーザーとしてOpenShiftクラスタにアクセスできること。

このビルドでは、`blueprints` ブランチ [ここ](https://github.com/yd-ono/rhel-edge-automation-arch/blob/blueprints/microshift/blueprint.toml) にホストされている MicroShift ブループリントを使用します。これは、MicroShiftの実行に必要なすべてのパッケージと、同じパスワードを持つ`redhat`という初期ユーザーを備えています。

### デフォルトパスワードの更新

より安全なインストールを行うには、ブループリントを修正し、パスワードハッシュを更新することをおすすめします。次のコマンドを使用して、新しいハッシュを生成します。

```shell
openssl passwd -6
```

`customizations.user`の`password`パラメータのハッシュを、上記で生成したハッシュで置き換えてください。

### 追加のコンテンツソース

以下の内容で `/tmp/microshift-additional-sources.json` というファイルを作成します。

```json
{
  "sources": {
    "rhocp": {
      "id": "rhocp",
      "name": "rhocp",
      "type": "yum-baseurl",
      "url": "https://cdn.redhat.com/content/dist/layered/rhel8/x86_64/rhocp/4.8/os",
      "check_gpg": false,
      "check_ssl": true,
      "system": true,
      "rhsm": true
    },
    "microshift": {
      "id": "microshift",
      "name": "MicroShift",
      "type": "yum-baseurl",
      "url": "https://download.copr.fedorainfracloud.org/results/@redhat-et/microshift/epel-8-x86_64/",
      "check_gpg": false,
      "check_ssl": false,
      "system": false,
      "rhsm": false
    }
  }
}
```

このファイルには、MicroShiftのrpmパッケージと、関連する依存関係をインストールするために Image Builder が必要とする追加のコンテンツソースが含まれています。

## MicroShiftのイメージをビルド

OpenShift CLIにログインし、`rfe` Namespaceへ変更します。

```shell
oc project rfe
```

以下のコマンドを実行して `rfe-oci-image-pipeline` パイプラインを実行し、`microshift` ブループリントをビルドします。

```shell
tkn pipeline start rfe-oci-image-pipeline \
     --workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
     -s rfe-automation \
     --use-param-defaults \
     -p blueprint-dir=microshift \
     -p blueprints-git-url=https://github.com/yd-ono/rhel-edge-automation-arch.git \
     -p blueprints-git-revision=blueprints \
     -p additional-content-sources='$(jq -c . /tmp/microshift-additional-sources.json | base64 -w0)'
```

ブループリントを更新して自分のgitリポジトリに保存した場合は、ブループリントのパラメータを自分のリポジトリに合わせて変更します。

`tkn`コマンドの出力には、ビルドの進捗を確認するための別のコマンドが表示されます。

_Note: イメージの構築作業には時間がかかります。

### パイプライン結果

各パイプラインの実行は、4つの結果を返します。

* `build-commit` - Image Builder からのビルドコミット ID。
* `image-builder-host` - パイプラインの実行時に使用される Image Builder のホストです．
* `image-path` - OCIコンテナのQuayレジストリ内の位置`。
* `image-tags` - コンテナに適用されるタグ（JSONリスト）。


```shell
$ tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-image-pipeline --limit 1
NAME                               STARTED     DURATION     STATUS
rfe-oci-image-pipeline-run-g8hzp   1 day ago   16 minutes   Succeeded
```

```shell
$ oc get pipelinerun -n rfe rfe-oci-image-pipeline-run-g8hzp -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "build-commit",
    "value": "04b92863-ab80-492e-b331-815530e34f3b"
  },
  {
    "name": "image-path",
    "value": "quay-quay-quay.apps.cluster/rfe/microshift"
  },
  {
    "name": "image-builder-host",
    "value": "10.129.2.9"
  },
  {
    "name": "image-tags",
    "value": "[\"latest\", \"0.0.1\"]"
  }
]
```

## OSTreeコミットしたOCIコンテナをステージングへ移行

QuayでOSTreeコミットしたOCIコンテナができたので、パイプラインを実行してOpenShiftのステージング環境としてデプロイしてみましょう。

プロジェクトのルートから、以下のコマンドを実行して `rfe-oci-stage-pipeline` パイプラインを実行し、前回のパイプライン (`rfe-oci-image-pipeline`) 実行で構築したOCIコンテナをデプロイします。

```shell
tkn pipeline start rfe-oci-stage-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/microshift \
-p image-tag=latest
```

このコマンドは、前のパイプラインの実行と似ていますが、以下のパラメータが使用されます。

* `-p image-path=quay-quay.apps.cluster.com/rfe/microshift` - Quayレジストリに保存されているOCIコンテナのパスです。
* `-p image-tag=latest` - _latest_ というタグのついたイメージを使用します。

### パイプライン結果

各パイプラインの実行は、1つの結果を返します。

* `content-path` - OSTreeリポジトリへのパス。

結果を表示するには、最新のパイプラインの実行を見つけます。例として、次のコマンドを使用します。

```shell
$ tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-stage-pipeline --limit 1
NAME                               STARTED     DURATION     STATUS
rfe-oci-stage-pipeline-run-cxkxq   1 day ago   13 minutes   Succeeded
```

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
$ oc get pipelinerun -n rfe rfe-oci-stage-pipeline-run-cxkxq -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "content-path",
    "value": "http://microshift-latest-rfe.apps.cluster.com/repo"
  }
]
```

## ステージングから本番環境へ移行

次に、ステージング環境から本番環境へOSTree Commitを同期させます。
プロジェクトのルートから、以下のコマンドを実行し、`rfe-oci-publish-content-pipeline`パイプラインを実行します。

```shell
tkn pipeline start rfe-oci-publish-content-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/microshift \
-p image-tag=latest 
```

このコマンドは、前のパイプラインの実行と似ていますが、以下のパラメータが使用されます。

* `-p image-path=quay-quay.apps.cluster.com/rfe/microshift` - Quayレジストリに保存されているOCIコンテナのパスです。
* `-p image-tag=latest` - _latest_ というタグのついたイメージを使用します。

### パイプライン結果

各パイプラインの実行は、1つの結果を返します。

* `content-path` - OSTreeリポジトリへのパス。

結果を表示するには、最新のパイプラインの実行を見つけます。例として、次のコマンドを使用します。

```shell
$ tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-publish-content-pipeline --limit 1
NAME                                         STARTED     DURATION   STATUS
rfe-oci-publish-content-pipeline-run-ptrpx   1 day ago   1 minute   Succeeded
```

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
$ oc get pipelinerun -n rfe rfe-oci-publish-content-pipeline-run-ptrpx -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "content-path",
    "value": "http://httpd-rfe.apps.cluster.com/microshift/latest"
  }
]
```

## キックスタートファイルを生成

`rfe-kickstart-pipeline`というTektonパイプラインは、NexusとHTTPDサーバーの両方にKickstartファイルを発行する役割を担っています。パイプラインはAnsibleを使用しているため、Jinjaベースのテンプレートがキーバリュー（特にOSTreeリポジトリの場所）を注入するために利用できます。

`rfe-oci-stage-pipeline`または`rfe-oci-publish-content-pipeline`のいずれかのパイプラインの結果からOSTreeリポジトリの場所を使用して、次のコマンドを実行します。

```shell
tkn pipeline start rfe-kickstart-pipeline \
-s rfe-automation \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
--use-param-defaults \
-p kickstart-path=microshift/kickstart.ks \
-p ostree-repo-url=file:///run/install/repo/ostree/repo
```

このコマンドは、前のパイプラインの実行と似ていますが、次のパラメータが使用されます。

前のコマンドを分解すると

* `-p kickstart-path` - 参照されるリポジトリで使用するキックスタートの場所です。デフォルトでは、このリポジトリの _kickstarts_ ブランチが使用されます。
* `-p ostree-repo-url` - OSTree リポジトリの場所です。このキックスタートは次のパイプライン実行時にインストーライメージに埋め込まれるため、OSTree リポジトリは ISO のローカルとなります。

`tkn pipeline` コマンドの出力は、ビルドの進捗を見るための別のコマンドを提供します。

### パイプライン結果

各パイプラインの実行は、2つの結果を返します。

* Artifact-repository-storage-url` - Nexus サーバー上のキックスタートの位置。
* `serving-storage-url` - HTTPD サーバー上のキックスタートの場所。

結果を表示するには、最新のパイプラインの実行を見つけます。例として、次のコマンドを使用します。

```shell
$ tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-kickstart-pipeline --limit 1
NAME                               STARTED          DURATION   STATUS
rfe-kickstart-pipeline-run-kqp5n   18 minutes ago   1 minute   Succeeded
```

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
$ oc get pipelinerun rfe-kickstart-pipeline-run-kqp5n -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "artifact-repository-storage-url",
    "value": "https://nexus-rfe.apps.cluster.com/repository/rfe-kickstarts/microshift/kickstart.ks"
  },
  {
    "name": "serving-storage-url",
    "value": "https://httpd-rfe.apps.cluster.com/kickstarts/microshift/kickstart.ks"
  }
]
```

## 自動ブート用RHEL for Edgeイメージ(ISO)を生成

Image Builderの機能のひとつに、インストーラに OSTree コミットを埋め込んだインストールメディアを構成する機能 (`image-type` `rhel-edge-installer` を使用) があります。このプロジェクトのパイプラインはさらに一歩進んで、生成された ISO にキックスタートファイルを埋め込み、埋め込まれたキックスタートを使用して RFE を自動的にインストールするように `EFI/BOOT/grub.cfg`/`isolinux/isolinux.cfg` を設定し直します。

プロジェクトのルートから、以下のコマンドを実行して `rfe-oci-iso-pipeline` パイプラインを実行します。

```shell
tkn pipeline start rfe-oci-iso-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p kickstart-url=$(oc get pipelinerun rfe-kickstart-pipeline-run-kqp5n -ojsonpath="{.status.pipelineResults[1].value}") \
-p ostree-repo-url=http://$(oc get route hello-world-latest -ojsonpath='{.status.ingress[*].host}')/microshift/latest
```

このコマンドは、前のパイプラインの実行と似ていますが、次のパラメータが使用されます。

* `-p kickstart-url` - ISO に埋め込まれるキックスタートへのパス。
* `-p ostree-repo-url` - ISO に埋め込まれる OSTree リポジトリへのパスです。

### パイプライン結果

各パイプラインの実行は、2つの結果を返します。

* `build-commit-id` - Image Builder からのビルドコミット ID。パイプラインの実行時に使用される Image Builder のホストです．
* `iso-url` - オートブートするISOの場所。

結果を表示するには、最新のパイプラインの実行を見つけます。例として、次のコマンドを使用します。

```shell
$ tkn pipelinerun list -n rfe --label tekton.dev/pipeline=rfe-oci-iso-pipeline --limit 1
NAME                             STARTED      DURATION     STATUS
rfe-oci-iso-pipeline-run-2lpwc   3 days ago   13 minutes   Succeeded
```

次に以下を実行すると、パイプラインの結果が表示されます。

```shell
$ oc get pipelinerun -n rfe rfe-oci-iso-pipeline-run-2lpwc -ojsonpath='{.status.pipelineResults}'
[
  {
    "name": "build-commit-id",
    "value": "9b4b3af4-c4f4-45a3-a5e7-cd1994838d26"
  },
  {
    "name": "image-builder-host",
    "value": "10.129.2.8"
  },
  {
    "name": "iso-url",
    "value": "https://httpd-rfe.apps.cluster.com/9b4b3af4-c4f4-45a3-a5e7-cd1994838d26-auto.iso"
  }
]
```

## デプロイ

ISO パイプラインが終了したら、`iso-url` の結果でリンクされている ISO を引っ張り出して、新しいシステムで起動させるだけです。ISOが起動すると、プロンプトなしで自動的にインストールが開始されるはずです。
