#!/bin/bash
# ----------------------------------
NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'
DARKGRAY='\033[1;30m'
LIGHTRED='\033[1;31m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHTBLUE='\033[1;34m'
LIGHTPURPLE='\033[1;35m'
LIGHTCYAN='\033[1;36m'
WHITE='\033[1;37m'
# ----------------------------------

#########################################################################################

function print_help { echo $'Usage\n\n' \
                           $'-s Subscription\n' \
                           $'-l Location\n' \
                           $'-r Resource Group\n' \
                           $'-k Ssh pubic key filename\n' \
                           $'-p Project root\n' \
                           $'-d Deployment Name\n' \
                           $'-a ACR Server\n' \
                           $'-v Image Version\n' \
                           $'-e Environment Tag (dev-qa-prod)\n' \
                           $'-t TLS Public Key File\n' \
                           $'-w TLS Private Certificate File\n' \
                           $'-i Identities Deployment Name\n' \
                           $'-b Identity Name\n' \
                           $'-n App Insights Instrumentation Key\n' \
                           $'-f Load Balancer FQDN\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts s:l:r:k:p:d:a:v:e:t:w:i:b:n:f:? option
do
case "${option}"
in
s) SUBSCRIPTION=${OPTARG};;
l) LOCATION=${OPTARG};;
r) RESOURCEGROUP=${OPTARG};;
k) SSHPUBKEYFILENAME=${OPTARG};;
p) PROJECTROOT=${OPTARG};;
d) DEVDEPLOYMENTNAME=${OPTARG};;
a) ACRSERVER=${OPTARG};;
v) VERSION=${OPTARG};;
e) ENVTAG=${OPTARG};;
t) TLSPUBKEYFILE=${OPTARG};;
w) TLSCERTFILE=${OPTARG};;
i) IDENTITIESDEPLOYMENTNAME=${OPTARG};;
b) IDENTITYNAME=${OPTARG};;
n) AIKEY=${OPTARG};;
f) LBFQDN=${OPTARG};;

?) print_help; exit 0;;
esac
done

function log-info {
  echo -e "${PURPLE}$1${NOCOLOR}"
}

function log-success {
  echo -e "${GREEN}$1${NOCOLOR}"
}

function log-verbose {
  echo "$1"
}

function log-warning {
  echo -e "${ORANGE}$1${NOCOLOR}"
}

function log-error {
  echo -e "${RED}$1${NOCOLOR}"
}

function prompt {
  read -p "$1"
}

#########################################################################################
# Package Name
imagename=dronescheduler
pathname=dronescheduler

#########################################################################################
log-warning "Deploying $imagename Service"

# commont input arguments
export SUBSCRIPTIONID=$SUBSCRIPTION
export LOCATION=$LOCATION
export RESOURCE_GROUP=$RESOURCEGROUP
export DEV_DEPLOYMENT_NAME=$DEVDEPLOYMENTNAME
export PROJECT_ROOT=$PROJECTROOT
export ACR_SERVER=$ACRSERVER
export IMAGE_VERSION=$VERSION
export ENV_TAG=$ENVTAG
export TLS_PUB_KEY_FILE=$TLSPUBKEYFILE
export TLS_CERT_FILE=$TLSCERTFILE
export IDENTITIES_DEPLOYMENT_NAME=$IDENTITIESDEPLOYMENTNAME
export IDENTITY_NAME=$IDENTITYNAME
export SRC_PATH=$PROJECT_ROOT/src/shipping/$pathname
export HELM_SRC_PATH=$PROJECT_ROOT/charts/$pathname/
export INGRESS_TLS_SECRET_NAME=$imagename-ingress-tls
export AI_IKEY=$AIKEY
export EXTERNAL_INGEST_FQDN=$LBFQDN

# core variables
imagetag=$ACR_SERVER/$imagename:$IMAGE_VERSION
release="$imagename-v$IMAGE_VERSION-$ENV_TAG"

# application specific variables to be fetched
export KEYVAULT_URI=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
export COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerCosmosDbName.value -o tsv)
export ENDPOINT_URL=$(az cosmosdb show -n $COSMOSDB_NAME -g $RESOURCE_GROUP --query documentEndpoint -o tsv)
export AUTH_KEY=$(az cosmosdb keys list -n $COSMOSDB_NAME -g $RESOURCE_GROUP --query primaryMasterKey -o tsv)
export DATABASE_NAME="invoicing"
export COLLECTION_NAME="utilization"
export PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerPrincipalResourceId.value -o tsv)
export PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $IDENTITY_NAME --query clientId -o tsv)

# Build the Docker image
log-info "Building docker image: $imagetag"
docker build --pull --compress -t $imagetag $SRC_PATH/.

# Push the image to ACR
log-info "Pushing docker image: $imagetag"
az acr login --name $ACR_NAME
docker push $imagetag

log-info "Deploying Helm release: $release"
MSYS_NO_PATHCONV=1 helm dependency update ../../charts/$pathname
MSYS_NO_PATHCONV=1 helm install $release ../../charts/$pathname \
     --set image.tag=$IMAGE_VERSION \
     --set image.repository=$imagename \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=$imagename \
     --set ingress.hosts[0].tls=false \
     --set identity.clientid=$PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$PRINCIPAL_RESOURCE_ID \
     --set keyvault.uri=$KEYVAULT_URI \
     --set cosmosdb.id=$DATABASE_NAME \
     --set cosmosdb.collectionid=$COLLECTION_NAME \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-$ENV_TAG 
