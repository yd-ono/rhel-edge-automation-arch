#!/bin/bash

oc project rfe

oc adm policy add-scc-to-user pipelines-scc -z rfe-automation

## RHEL for Edgeイメージのビルド
tkn pipeline start rfe-oci-image-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p blueprint-dir=hello-world 

## OSTreeコミットしたOCIコンテナをステージングへ移行
tkn pipeline start rfe-oci-stage-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/hello-world \
-p image-tag=latest

## ステージングから本番環境へ移行
tkn pipeline start rfe-oci-publish-content-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p image-path=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/hello-world \
-p image-tag=latest 

## キックスタートファイルを生成
tkn pipeline start rfe-kickstart-pipeline \
-s rfe-automation \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
--use-param-defaults \
-p kickstart-path=ibm-weather-forecaster/kickstart.ks \
-p ostree-repo-url=$(oc get pipelinerun -n rfe rfe-oci-publish-content-pipeline-run-8sf7z -ojsonpath='{.status.pipelineResults[*].value}')

## 自動ブート用RHEL for Edgeイメージ(ISO)を生成
tkn pipeline start rfe-oci-iso-pipeline \
--workspace name=shared-workspace,volumeClaimTemplateFile=examples/pipelines/volumeclaimtemplate.yaml \
-s rfe-automation \
--use-param-defaults \
-p kickstart-url=$(oc get pipelinerun rfe-kickstart-pipeline-run-4g869 -ojsonpath="{.status.pipelineResults[1].value}") \
-p ostree-repo-url=$(oc get pipelinerun -n rfe rfe-oci-publish-content-pipeline-run-8sf7z -ojsonpath='{.status.pipelineResults[*].value}')


export IMAGE_PATH=$(oc get route -n quay quay-quay -ojsonpath='{.spec.host}')/rfe/hello-world
export OSTREE_REPO=$(oc get pipelinerun -n rfe rfe-oci-publish-content-pipeline-run-8sf7z -ojsonpath='{.status.pipelineResults[*].value}')/refs/heads/rhel/8/x86_64/edge
export NEXUS=$(oc get pipelinerun rfe-kickstart-pipeline-run-4g869 -ojsonpath="{.status.pipelineResults[0].value}")
export ISO_URL=

echo "ISO: $ISO_URL"
echo "QUAY: $IMAGE_PATH"
echo "OSTREE_REPO: $OSTREE_REPO"
echo "NEXUS: $NEXUS"
