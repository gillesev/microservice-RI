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
                           $'-d ADO Organization Name\n' \
                           $'-e ADO Project Name\n' \
                           $'-s Subscription\n' \
                           $'-t Variables (key1=value1 key2=value2 separated by a space)\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts d:e:s:t:? option
do
case "${option}"
in
d) AZUREDEVOPSORGNAME=${OPTARG};;
e) AZUREDEVOPSPROJECTNAME=${OPTARG};;
s) SUBSCRIPTIONID=${OPTARG};;
t) ENVVARIABLES=${OPTARG};;
?) print_help; exit 0;;
esac
done

# assign default values

log-warning "ADO Infrastructure Cross Pipelines Variables DEPLOYMENT: STARTING"
log-verbose "Variables used in CI Pipelines that do NOT depend on target environment (dev/qa/uat/prod)"
log-verbose "This script needs to be executed when the Azure Infrastructure and the ADO Infrastructure have been deployed"

log-info "ADO Organization Name: $AZUREDEVOPSORGNAME"
log-info "ADO Project Name: $AZUREDEVOPSPROJECTNAME"
log-info "Subscription: $SUBSCRIPTIONID"
log-info "Variables: $ENVVARIABLES"

log-warning "Press [ENTER] key to proceed"
prompt ""

if [[ -z "$AZUREDEVOPSORGNAME" \
  || -z "$AZUREDEVOPSPROJECTNAME" \
  || -z "$SUBSCRIPTIONID" \
  || -z "$ENVVARIABLES" ]];then
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
# Set Main Variables
AZURE_DEVOPS_ORG=https://dev.azure.com/$AZUREDEVOPSORGNAME

#########################################################################################
# Add ADO variable groups/variables
varGroup="$AZUREDEVOPSPROJECTNAME-variables"
log-info "Adding ADO variable for group: $varGroup"
log-verbose "Adding variables: $ENVVARIABLES"

az pipelines variable-group create \
  --name $varGroup \
  --variables $ENVVARIABLES \
  --org $AZUREDEVOPSORG \
  --project $AZUREDEVOPSPROJECTNAME \
  --subscription $SUBSCRIPTION_ID

varGrpId=$(az pipelines variable-group list --org $AZURE_DEVOPS_ORG --project $AZUREDEVOPSPROJECTNAME --query "[?name=='$varGroup'].id" -o tsv)

if [ -z $varGrpId ];then
  log-error "Failed creating the pipeline variable group: $varGroup"
  exit 1
fi

# update the variable group to authorize all pipelines to use it.
az pipelines variable-group update \
  --id $varGrpId \
  --org $AZURE_DEVOPS_ORG \
  --project $AZUREDEVOPSPROJECTNAME \
  --subscription $SUBSCRIPTION_ID \
  --authorize true

log-warning "ADO Infrastructure Cross Pipelines Variables DEPLOYMENT: COMPLETE"