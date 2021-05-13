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

# ----------------------------------

#########################################################################################
servicename=package

function print_help { echo $'Usage\n\n' \
                           $'-d ADO Organization Name\n' \
                           $'-e ADO Project Name\n' \
                           $'-r Source Code Repository URL\n' \
                           $'-s Subscription\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts d:e:r:s:? option
do
case "${option}"
in
d) AZUREDEVOPSORGNAME=${OPTARG};;
e) AZUREDEVOPSPROJECTNAME=${OPTARG};;
r) SRCCODEREPOURL=${OPTARG};;
s) SUBSCRIPTIONID=${OPTARG};;
?) print_help; exit 0;;
esac
done

# assign default values

log-warning "'$servicename' Service CI Pipeline DEPLOYMENT: STARTING"

log-info "ADO Organization Name:  $AZUREDEVOPSORGNAME"
log-info "ADO Project Name:  $AZUREDEVOPSPROJECTNAME"
log-info "Source Code Repository: $SRCCODEREPOURL"
log-info "Subscription: $SUBSCRIPTIONID"

log-warning "Press [ENTER] key to proceed"
prompt ""

if [[ -z "$AZUREDEVOPSORGNAME" \
  || -z "$AZUREDEVOPSPROJECTNAME" \
  || -z "$SUBSCRIPTIONID" \
  || -z "$SRCCODEREPOURL" ]];then
  print_help;
  exit 2
fi

#########################################################################################
## Logging into Azure CLI

log-info "Checking current Azure CLI logged in user"
userObjectId=$(az ad signed-in-user show --query objectId -o tsv)

if [ -z "$userObjectId" ];then
  # silently log in
  az login > /dev/null
fi

az account set --subscription=$SUBSCRIPTIONID

export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
export TENANT_ID=$(az account show --query tenantId --output tsv)

#########################################################################################
## Initialize Main variables

export AZURE_DEVOPS_ORG=https://dev.azure.com/$AZUREDEVOPSORGNAME
export AZURE_DEVOPS_VSRM_ORG=https://vsrm.dev.azure.com/$AZUREDEVOPSORGNAME
export PROJECT_PATH=src/shipping/$servicename
export AZURE_CI_PIPELINE_NAME=$servicename-ci
GITHUB_SERVICE_CONN_NAME=msri-github-ci-service-connection

#########################################################################################

# find the service endpoint connection id
log-info "Checking ADO Project's GitHub Service Endpoint Id"
serviceEndpointId=$(az devops service-endpoint list \
  --org $AZURE_DEVOPS_ORG \
  --project $AZUREDEVOPSPROJECTNAME \
  --query "[?name=='$GITHUB_SERVICE_CONN_NAME']|[0].id" -o tsv)

if [ -z $serviceEndpointId ];then
  log-error "Cannot find the GitHub Project's ARM Service Endpoint Id for service connection: $GITHUB_SERVICE_CONN_NAME"
  log-warning "'$servicename' Service CI Pipeline DEPLOYMENT: COMPLETE"
  exit 1
else
  log-verbose "ADO Project's GitHub Service Endpoint Id: $serviceEndpointId"
fi

#########################################################################################
# create CI pipeline
log-verbose "Service Connection Id for the $AZURE_CI_PIPELINE_NAME CI Pipeline is: $serviceEndpointId"

az pipelines create \
  --name $AZURE_CI_PIPELINE_NAME \
  --description "package CI Pipeline" \
  --organization $AZURE_DEVOPS_ORG \
  --project MicroService-RI \
  --branch master \
  --repository-type github \
  --repository $SRCCODEREPOURL \
  --yaml-path $PROJECT_PATH/azure-pipelines.yml \
  --service-connection $serviceEndpointId \
  --skip-run true

#########################################################################################
# Verifying CI Pipeline Status
log-info "Checking status of $AZURE_CI_PIPELINE_NAME CI pipeline"

export AZURE_DEVOPS_PACKAGE_BUILD_ID=$(az pipelines build definition list \
  --organization $AZURE_DEVOPS_ORG \
  --project $AZUREDEVOPSPROJECTNAME \
  --query "[?name=='$AZURE_CI_PIPELINE_NAME'].id" -o tsv)

if [ -z $AZURE_DEVOPS_PACKAGE_BUILD_ID ];then
  log-error "$AZURE_CI_PIPELINE_NAME CI Pipeline failed being created"
  log-warning "'$servicename' Service CI Pipeline DEPLOYMENT: COMPLETE"
  exit 1
else
  log-success "$AZURE_CI_PIPELINE_NAME CI Pipeline Id: $AZURE_DEVOPS_PACKAGE_BUILD_ID successfully created"
fi

#########################################################################################
# Done

log-warning "'$servicename' Service CI Pipeline DEPLOYMENT: COMPLETE"