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
                           $'-t Variables\n' \
                           $'-u Environment Name\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts d:e:s:t:u:? option
do
case "${option}"
in
d) AZUREDEVOPSORG=${OPTARG};;
e) AZUREDEVOPSPROJECTNAME=${OPTARG};;
s) SUBSCRIPTIONID=${OPTARG};;
t) ENVNAME=${OPTARG};;
u) ENVVARIABLES=${OPTARG};;
?) print_help; exit 0;;
esac
done

# assign default values

log-warning "ADO Infrastructure Environment Variables DEPLOYMENT: STARTING"

log-info "ADO Organization URL:  $AZUREDEVOPSORG"
log-info "ADO Project Name:  $AZUREDEVOPSPROJECTNAME"
log-info "Subscription: $SUBSCRIPTIONID"
log-info "Environment Name: $ENVNAME"
log-info "Variables: $ENVVARIABLES"

log-warning "Press [ENTER] key to proceed"
prompt ""

if [[ -z "$AZUREDEVOPSORG" \
  || -z "$AZUREDEVOPSPROJECTNAME" \
  || -z "$SUBSCRIPTIONID" \
  || -z "$ENVNAME" \
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
# Add ADO variable groups/variables
varGroup="$AZUREDEVOPSPROJECTNAME-variables-$ENVNAME"
log-info "Adding ADO variable for group: $varGroup"
log-verbose "Adding variables: $ENVVARIABLES"

az pipelines variable-group create \
  --name $varGroup \
  --variables $ENVVARIABLES \
  --org $AZURE_DEVOPS_ORG \
  --project $AZURE_DEVOPS_PROJECT_NAME \
  --subscription $SUBSCRIPTION_ID

log-warning "ADO Infrastructure Environment Variables DEPLOYMENT: COMPLETE"
