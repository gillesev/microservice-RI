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

function print_help { echo $'Usage\n\n' \
                           $'-d ADO Organization URL\n' \
                           $'-e ADO Project Name\n' \
                           $'-s Subscription\n' \
                           $'-r GitHub Repo\n' \
                           $'-t GitHub PAT\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts d:e:s:r:t:? option
do
case "${option}"
in
d) AZUREDEVOPSORG=${OPTARG};;
e) AZUREDEVOPSPROJECTNAME=${OPTARG};;
s) SUBSCRIPTIONID=${OPTARG};;
r) SRCCODEREPOURL=${OPTARG};;
t) GITHUBPAT=${OPTARG};;
?) print_help; exit 0;;
esac
done

# assign default values

log-warning "ADO Infrastructure DEPLOYMENT: STARTING"

log-info "ADO Organization URL:  $AZUREDEVOPSORG"
log-info "ADO Project Name:  $AZUREDEVOPSPROJECTNAME"
log-info "Subscription: $SUBSCRIPTIONID"
log-info "GitHub Repo: $SRCCODEREPOURL"
log-info "GitHub PAT: *********************"

log-warning "Press [ENTER] key to proceed"
prompt ""

if [[ -z "$AZUREDEVOPSORG" \
  || -z "$AZUREDEVOPSPROJECTNAME" \
  || -z "$SUBSCRIPTIONID" \
  || -z "$SRCCODEREPOURL" \
  || -z "$GITHUBPAT" ]];then
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

AZURE_DEVOPS_ORG=$AZUREDEVOPSORG
AZURE_DEVOPS_PROJECT_NAME=$AZUREDEVOPSPROJECTNAME
AZURE_PIPELINES_SERVICE_CONN_NAME=msri-cicd-service-connection
GITHUB_SERVICE_CONN_NAME=msri-github-ci-service-connection
PROJECT_ROOT=.

#########################################################################################
# create ADO Infrastructure

# create ADO repo
log-info "Creating ADO Project: $AZURE_DEVOPS_PROJECT_NAME"
az devops project create \
  --name $AZURE_DEVOPS_PROJECT_NAME \
  --organization $AZURE_DEVOPS_ORG

# create service principal for Azure Pipelines with default 'Contributor' role
# e.g. has access to all azure services with read/list permissions.
log-info "Creating 'Contributor' AAD Service Principal"

export SP_DETAILS=$(az ad sp create-for-rbac --role="Contributor" -o json) && \
export SP_APP_ID=$(echo $SP_DETAILS | jq ".appId" -r) && \
export SP_CLIENT_SECRET=$(echo $SP_DETAILS | jq ".password" -r) && \
export SP_OBJECT_ID=$(az ad sp show --id $SP_APP_ID -o tsv --query objectId)

log-info "Checking ADO Project's ARM Service Connection: $AZURE_PIPELINES_SERVICE_CONN_NAME"

serviceEndpointId=$(az devops service-endpoint list \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME \
  --query "[?name=='$AZURE_PIPELINES_SERVICE_CONN_NAME']|[0].id")

if [ -z $serviceEndpointId ];then
  log-info "Creating ADO Project's ARM Service Connection"
  
  export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY=$SP_CLIENT_SECRET
  az devops service-endpoint azurerm create \
    --name $AZURE_PIPELINES_SERVICE_CONN_NAME \
    --org $AZURE_DEVOPS_ORG \
    --project $AZURE_DEVOPS_PROJECT_NAME \
    --azure-rm-tenant-id $TENANT_ID \
    --azure-rm-subscription-id $SUBSCRIPTION_ID \
    --azure-rm-subscription-name "$SUBSCRIPTION_NAME" \
    --azure-rm-service-principal-id $SP_APP_ID

  serviceEndpointId=$(az devops service-endpoint list \
    --org $AZURE_DEVOPS_ORG \
    --project $AZURE_DEVOPS_PROJECT_NAME \
    --query "[?name=='$AZURE_PIPELINES_SERVICE_CONN_NAME']|[0].id")

  # This API does not seem to work and return ERROR: Page not found.  Operation returned a 404 status code.
  log-info "Updating ADO Project's ARM Service Connection"
  az devops service-endpoint update \
    --id $serviceEndpointId \
    --organization $AZURE_DEVOPS_ORG \
    --project $AZURE_DEVOPS_PROJECT_NAME \
    --subscription $SUBSCRIPTIONID \
    --enable-for-all true
fi

serviceEndpointId=$(az devops service-endpoint list \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME \
  --query "[?name=='$AZURE_PIPELINES_SERVICE_CONN_NAME']|[0].id")

if [ -z $serviceEndpointId ];then
  log-error "Cannot find nor create ADO Project's ARM Service Connection: $AZURE_PIPELINES_SERVICE_CONN_NAME"
  exit 1
else
  log-info "ADO Project's ARM Service Connection: $AZURE_PIPELINES_SERVICE_CONN_NAME is valid"
fi

log-info "Checking ADO Project's GitHub Service Connection: $GITHUB_SERVICE_CONN_NAME"

serviceEndpointId=$(az devops service-endpoint list \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME \
  --query "[?name=='$GITHUB_SERVICE_CONN_NAME']|[0].id")

if [ -z $serviceEndpointId ];then
  log-info "Creating ADO Project's GitHub Service Connection"
  
  export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY=$SP_CLIENT_SECRET
  export AZURE_DEVOPS_EXT_GITHUB_PAT=$GITHUBPAT

  az devops service-endpoint github create \
  --github-url $SRCCODEREPOURL \
  --name $GITHUB_SERVICE_CONN_NAME \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME

  serviceEndpointId=$(az devops service-endpoint list \
    --org $AZURE_DEVOPS_ORG \
    --project $AZURE_DEVOPS_PROJECT_NAME \
    --query "[?name=='$GITHUB_SERVICE_CONN_NAME']|[0].id")

  # This API does not seem to work and return ERROR: Page not found.  Operation returned a 404 status code.
  log-info "Updating ADO Project's GitHub Service Connection"
  az devops service-endpoint update \
    --id $serviceEndpointId \
    --organization $AZURE_DEVOPS_ORG \
    --project $AZURE_DEVOPS_PROJECT_NAME \
    --subscription $SUBSCRIPTIONID \
    --enable-for-all true
fi

serviceEndpointId=$(az devops service-endpoint list \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME \
  --query "[?name=='$GITHUB_SERVICE_CONN_NAME']|[0].id")

if [ -z $serviceEndpointId ];then
  log-error "Cannot find nor create ADO Project's GitHub Service Connection: $GITHUB_SERVICE_CONN_NAME"
  exit 1
else
  log-info "ADO Project's GitHub Service Connection: $GITHUB_SERVICE_CONN_NAME is valid"    
fi

log-warning "ADO Infrastructure DEPLOYMENT: COMPLETE"