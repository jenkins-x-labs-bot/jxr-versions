#!/usr/bin/env bash
set -e
set -x

# setup environment
KUBECONFIG="/tmp/jxhome/config"

mkdir -p $JX_HOME/git

echo "current HOME is $HOME"
export HOME="/builder/home"

#JX_HOME="/tmp/jxhome"
export JX_HOME="/home"

# copy the binary plugins
# TODO is this required?
mkdir -p $JX_HOME/plugins/jx/bin
cp -r $JX_HOME/plugins/jx/bin $JX_HOME/plugins/bin

#cp -r $HOME/.jx/plugins $JX_HOME/plugins

echo "the binary plugins in the temporary jx home dir are:"
ls -al $JX_HOME/plugins/bin
ls -al $JX_HOME/plugins/jx/bin

jx --version

export GH_USERNAME="jenkins-x-labs-bot"
export GH_EMAIL="jenkins-x@googlegroups.com"
export GH_OWNER="cb-kubecd"

export PROJECT_ID=jenkins-x-labs-bdd
export CREATED_TIME=$(date '+%a-%b-%d-%Y-%H-%M-%S')
export CLUSTER_NAME="${BRANCH_NAME,,}-$BUILD_NUMBER-bdd-gke"
export ZONE=europe-west1-c
export LABELS="branch=${BRANCH_NAME,,},cluster=bdd-gke,create-time=${CREATED_TIME,,}"

# lets setup git
git config --global --add user.name JenkinsXBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD test with JX_HOME = $JX_HOME"

# replace the credentials file with a single user entry
echo "https://${GH_USERNAME//[[:space:]]}:${GH_ACCESS_TOKEN//[[:space:]]}@github.com" > $JX_HOME/git/credentials

echo "creating cluster $CLUSTER_NAME in project $PROJECT_ID with labels $LABELS"

# lets find the current cloud resources version
export CLOUD_RESOURCES_VERSION=$(grep  'version: ' /workspace/source/git/github.com/jenkins-x-labs/cloud-resources.yml | awk '{ print $2}')
echo "found cloud-resources version $CLOUD_RESOURCES_VERSION"

git clone -b v${CLOUD_RESOURCES_VERSION} https://github.com/jenkins-x-labs/cloud-resources.git
cloud-resources/gcloud/create_cluster.sh

# TODO remove once we remove the code from the multicluster branch of jx:
export JX_SECRETS_YAML=/tmp/secrets.yaml

echo "using the version stream ref: $PULL_PULL_SHA"

# create the boot git repository
jxl boot create -b --env dev --provider=gke --version-stream-ref=$PULL_PULL_SHA --env-git-owner=$GH_OWNER --project=$PROJECT_ID --cluster=$CLUSTER_NAME --zone=$ZONE --out giturl.txt

# import secrets...
echo "secrets:
  adminUser:
    username: admin
    password: $JENKINS_PASSWORD
  hmacToken: $GH_ACCESS_TOKEN
  pipelineUser:
    username: $GH_USERNAME
    token: $GH_ACCESS_TOKEN
    email: $GH_EMAIL" > /tmp/secrets.yaml

jxl boot secrets import -f /tmp/secrets.yaml --git-url `cat giturl.txt`

jxl boot run -b --job


# lets make sure jx defaults to helm3
export JX_HELM3="true"

gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID
jx ns jx

# diagnostic commands to test the image's kubectl
kubectl version

# for some reason we need to use the full name once for the second command to work!
kubectl get environments
kubectl get env
kubectl get env dev -oyaml

# TODO not sure we need this?

helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io


export JX_DISABLE_DELETE_APP="true"

export GIT_ORGANISATION="$GH_OWNER"


# lets avoid the git/credentials causing confusion during the test
export XDG_CONFIG_HOME=$JX_HOME

# run the BDD tests
bddjx -ginkgo.focus=golang -test.v

echo cleaning up cloud resources
curl https://raw.githubusercontent.com/jenkins-x-labs/cloud-resources/v$CLOUD_RESOURCES_VERSION/gcloud/cleanup-cloud-resurces.sh | bash
gcloud container clusters delete $CLUSTER_NAME --zone $ZONE --quiet
