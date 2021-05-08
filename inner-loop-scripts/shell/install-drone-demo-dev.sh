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
                           $'-i Skip Azure Infrastructure Deployment\n' \
                           $'-j Azure Infrastructure Deployment Id\n' \
                           $'-m Skip Client Tooling Install\n' \
                           $'-n Skip AKS Infrastructure Deployment\n' \
                           $'-o Skip Application Deployment\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts s:l:r:k:i:j:m:n:o:? option
do
case "${option}"
in
s) SUBSCRIPTION=${OPTARG};;
l) LOCATION=${OPTARG};;
r) RESOURCEGROUP=${OPTARG};;
k) SSHPUBKEYFILENAME=${OPTARG};;
i) SKIPDEPLOYMENT=${OPTARG};;
j) DEPOYSUFFIX=${OPTARG};;
m) SKIPCLIENTTOOLINGINSTALL=${OPTARG};;
n) SKIPK8SDEPLOYMENT=${OPTARG};;
o) SKIPAPPDEPLOYMENT=${OPTARG};;
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

if [ -z "$SKIPDEPLOYMENT" ];then
  SKIPDEPLOYMENT="false"
fi

if [ -z "$DEPOYSUFFIX" ];then
  DEPOYSUFFIX=""
fi

if [ -z "$SKIPCLIENTTOOLINGINSTALL" ];then
  SKIPCLIENTTOOLINGINSTALL="false"
fi

if [ -z "$SKIPK8SDEPLOYMENT" ];then
  SKIPK8SDEPLOYMENT="false"
fi

if [ -z "$SKIPAPPDEPLOYMENT" ];then
  SKIPAPPDEPLOYMENT="false"
fi

log-warning "DEPLOYMENT: STARTING"

log-info "Subscription: $SUBSCRIPTION"
log-info "Location: $LOCATION"
log-info "Resource Group: $RESOURCEGROUP"
log-info "SSH Public key file: $SSHPUBKEYFILENAME"
log-info "Skip Azure Infrastructure Deployment: $SKIPDEPLOYMENT"
log-info "Azure Infrastructure Deployment Id: $DEPOYSUFFIX"
log-info "Skip Client Tooling Install: $SKIPCLIENTTOOLINGINSTALL"
log-info "Skip AKS Infrastructure Deployment: $SKIPK8SDEPLOYMENT"
log-info "Skip Application Deployment: $SKIPAPPDEPLOYMENT"

log-warning "Press [ENTER] key to proceed"
prompt ""

if [[ -z "$SUBSCRIPTION" || -z "$LOCATION" || -z "$RESOURCEGROUP" || -z "$SSHPUBKEYFILENAME" ]]; then
print_help;
exit 2
fi

#########################################################################################
## Initialize Main variables

if [ $SKIPDEPLOYMENT == "true" ];then
export DEPLOYMENT_SUFFIX=$DEPOYSUFFIX
else
export DEPLOYMENT_SUFFIX=$(date +%s%N)
fi

export SUBSCRIPTIONID=$SUBSCRIPTION
export LOCATION=$LOCATION
export RESOURCE_GROUP=$RESOURCEGROUP
export DEV_PREREQ_DEPLOYMENT_NAME=azuredeploy-prereqs-${DEPLOYMENT_SUFFIX}-dev
export DEV_DEPLOYMENT_NAME=azuredeploy-${DEPLOYMENT_SUFFIX}-dev
export SSH_PUBLIC_KEY_FILE=$SSHPUBKEYFILENAME

log-warning "Starting Deployment No: $DEPLOYMENT_SUFFIX"

#########################################################################################
## Logging into Azure CLI

log-info "Checking current Azure CLI logged in user"
userObjectId=$(az ad signed-in-user show --query objectId -o tsv)

if [ -z "$userObjectId" ];then
   az login > /dev/null
fi

az account set --subscription=$SUBSCRIPTIONID

export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
export TENANT_ID=$(az account show --query tenantId --output tsv)

if [ -f "$SSH_PUBLIC_KEY_FILE" ];then
    export TEST=SSH_PUBLIC_KEY_FILE
else
    exit 1
fi

export PROJECT_ROOT=./
export K8S=$PROJECT_ROOT/k8s
export HELM_CHARTS=$PROJECT_ROOT/charts

#########################################################################################
if [ $SKIPDEPLOYMENT == "true" ];then
  log-info "SKIP: Cleaning up previous deployment resource left overs"
else
  log-info "Cleaning up previous deployment resource left overs"
  log-verbose "Cleaning up deleted pending keyvault resources"
  az keyvault list-deleted --query "[].{name: name}" -o tsv
  az keyvault purge --name dev-wf-nopqttanbbbi2
  az keyvault purge --name dev-ds-nopqttanbbbi2
  az keyvault purge --name dev-d-nopqttanbbbi2
fi

#########################################################################################
## Create Service Principal with 'Contributor' role

if [ $SKIPDEPLOYMENT == "true" ];then
  log-info "SKIP: Creating Service Principal with Contributor role"
else
  log-info "Creating Service Principal with Contributor role"

  export SP_DETAILS=$(az ad sp create-for-rbac --role="Contributor" -o json) && \
  export SP_APP_ID=$(echo $SP_DETAILS | jq ".appId" -r) && \
  export SP_CLIENT_SECRET=$(echo $SP_DETAILS | jq ".password" -r) && \
  export SP_OBJECT_ID=$(az ad sp show --id $SP_APP_ID -o tsv --query objectId)

fi

#########################################################################################
# Deploy the resource groups and managed identities
# These are deployed first in a separate template to avoid propagation delays with AAD

if [ $SKIPDEPLOYMENT == "true" ];then
  log-info "SKIP: Deploying Azure Infrastructure Pre-requisites - $DEV_PREREQ_DEPLOYMENT_NAME..."
else
  log-warning "Deploying Azure Infrastructure Pre-requisites - $DEV_PREREQ_DEPLOYMENT_NAME..."

  az deployment sub create \
      --name $DEV_PREREQ_DEPLOYMENT_NAME \
      --location $LOCATION \
      --template-file ${PROJECT_ROOT}/azuredeploy-prereqs.json \
      --parameters resourceGroupName=$RESOURCE_GROUP \
                  resourceGroupLocation=$LOCATION \
                  environmentName=dev || sleep 15;

  printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh
fi

#########################################################################################
log-info "Validating Deployment - $DEV_PREREQ_DEPLOYMENT_NAME..."

deploy_status=$(az deployment sub show --name $DEV_PREREQ_DEPLOYMENT_NAME --query "properties.provisioningState" -o tsv)

if [ $deploy_status ==  "Succeeded" ]
then
  log-success "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME succeeded"
else
  log-error "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME failed"
  exit 1
fi

#########################################################################################
## Core Infrastructure Deployment

export IDENTITIES_DEPLOYMENT_NAME=$(az deployment sub show -n $DEV_PREREQ_DEPLOYMENT_NAME --query properties.outputs.identitiesDeploymentName.value -o tsv)
export DELIVERY_ID_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.deliveryIdName.value -o tsv)
export DELIVERY_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $DELIVERY_ID_NAME --query principalId -o tsv)
export DRONESCHEDULER_ID_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerIdName.value -o tsv)
export DRONESCHEDULER_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $DRONESCHEDULER_ID_NAME --query principalId -o tsv)
export WORKFLOW_ID_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.workflowIdName.value -o tsv)
export WORKFLOW_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $WORKFLOW_ID_NAME --query principalId -o tsv)
export RESOURCE_GROUP_ACR=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.acrResourceGroupName.value -o tsv)

# Wait for AAD propagation
until az ad sp show --id ${DELIVERY_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
until az ad sp show --id ${DRONESCHEDULER_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
until az ad sp show --id ${WORKFLOW_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done

export KUBERNETES_VERSION=$(az aks get-versions -l $LOCATION --query "orchestrators[?default!=null].orchestratorVersion" -o tsv)

if [ $SKIPDEPLOYMENT == "true" ];then
  log-info "SKIP: Deploying Azure Core Infrastructure - $DEV_DEPLOYMENT_NAME..."
else
  log-warning "Deploying Azure Core Infrastructure - $DEV_DEPLOYMENT_NAME..."

  az deployment group create -g $RESOURCE_GROUP --name $DEV_DEPLOYMENT_NAME --template-file ${PROJECT_ROOT}/azuredeploy.json \
  --parameters \
      environmentName=dev \
      servicePrincipalClientId=${SP_APP_ID} \
      servicePrincipalClientSecret=${SP_CLIENT_SECRET} \
      servicePrincipalId=${SP_OBJECT_ID} \
      kubernetesVersion=${KUBERNETES_VERSION} \
      sshRSAPublicKey="$(cat ${SSH_PUBLIC_KEY_FILE})" \
      deliveryIdName=${DELIVERY_ID_NAME} \
      deliveryPrincipalId=${DELIVERY_ID_PRINCIPAL_ID} \
      droneSchedulerIdName=${DRONESCHEDULER_ID_NAME} \
      droneSchedulerPrincipalId=${DRONESCHEDULER_ID_PRINCIPAL_ID} \
      workflowIdName=${WORKFLOW_ID_NAME} \
      workflowPrincipalId=${WORKFLOW_ID_PRINCIPAL_ID} \
      acrResourceGroupName=${RESOURCE_GROUP_ACR}

fi

log-info "Validating Deployment - $DEV_DEPLOYMENT_NAME..."

deploy_status=$(az deployment group show --name $DEV_DEPLOYMENT_NAME -g $RESOURCE_GROUP --query "properties.provisioningState" -o tsv)

if [ $deploy_status ==  "Succeeded" ]
then
  log-success "Deployment - $DEV_DEPLOYMENT_NAME succeeded"
else
  log-error "Deployment - $DEV_DEPLOYMENT_NAME failed"
  exit 1
fi

export ACR_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.acrName.value -o tsv)
export ACR_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
export CLUSTER_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.aksClusterName.value -o tsv)
export AI_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.appInsightsName.value -o tsv)
export AI_IKEY=$(az resource show \
                    -g $RESOURCE_GROUP \
                    -n $AI_NAME \
                    --resource-type "Microsoft.Insights/components" \
                    --query properties.InstrumentationKey \
                    -o tsv)
deliveryKeyVaultUri=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryKeyVaultUri.value -o tsv)
droneSchedulerKeyVaultUri=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
workflowKeyVaultName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.workflowKeyVaultName.value -o tsv)
acrDeploymentName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.acrDeploymentName.value -o tsv)
appInsightsName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.appInsightsName.value -o tsv)
ingress_ns=ingress-controllers
ingress_helm_repo=ingress-nginx
ingress_service_proposed_name="nginx-ingress-dev"
ingress_service_fdqn="$ingress_service_proposed_name-$ingress_helm_repo-controller"

log-verbose "Outputs for Deployment - $DEV_DEPLOYMENT_NAME\n"
log-verbose "ACR Deployment Name: $acrDeploymentName"
log-verbose "ACR Name: $ACR_NAME"
log-verbose "ACR Server: $ACR_SERVER"
log-verbose "AKS Cluster Name: $CLUSTER_NAME"
log-verbose "Key Vault (Delivery) URI: $deliveryKeyVaultUri"
log-verbose "Key Vault (Drone Scheduler) URI: $droneSchedulerKeyVaultUri"
log-verbose "Key Vault (Workflow) Name: $workflowKeyVaultName"
log-verbose "AppInsights Name: $appInsightsName"

#########################################################################################
## Client Tooling Install

if [ $SKIPCLIENTTOOLINGINSTALL == "true" ];then
  log-info "SKIP: Deploying Client Tooling chain: kubectl/Helm"
else
  log-warning "Installing kubectl..."
  az aks install-cli

  log-warning "Installing Helm..."
  choco install kubernetes-helm
fi

#########################################################################################
# Get the Kubernetes cluster credentials
az aks get-credentials --resource-group=$RESOURCE_GROUP --name=$CLUSTER_NAME --overwrite-existing --admin

#########################################################################################
# Get AKS Configuration - Core Infrastructure continue...

if [ $SKIPK8SDEPLOYMENT == "true" ];then
  log-info "SKIP: AKS Infrastructure Deployment - $DEV_DEPLOYMENT_NAME..."
else
  log-warning "AKS Infrastructure Deployment - $DEV_DEPLOYMENT_NAME..."
  # Create namespaces
  kubectl create namespace backend-dev

  log-info "Configuring RBAC for Application Insights..."
  # add RBAC for AppInsights
  kubectl apply -f $K8S/k8s-rbac-ai.yaml

  # add AAD pod identity
  log-info "Deploying & Configuring AAD POD Identity..."
  az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
  az provider register -n Microsoft.ContainerService

  # setup AAD pod identity
  helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  helm repo update
  helm install aad-pod-identity aad-pod-identity/aad-pod-identity --set installCRDs=true --set nmi.allowNetworkPluginKubenet=true  --namespace kube-system

  # setup K8s DeamonSet with flex volume mount
  kubectl create -f https://raw.githubusercontent.com/Azure/kubernetes-keyvault-flexvol/master/deployment/kv-flexvol-installer.yaml

  # setup KeyVault CSI driver
  secretStoreCSIDriverUri=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
  secretStoreCSIDriverHelmRepo=csi-secrets-store-provider-azure
  log-info "Deploying the Azure Secrets Store CSI driver provider..."
  log-info "Installing Helm chart: $secretStoreCSIDriverUri"

  helm repo add $secretStoreCSIDriverHelmRepo $secretStoreCSIDriverUri
  helm install csi $secretStoreCSIDriverHelmRepo/$secretStoreCSIDriverHelmRepo

  # setup NGINX ingress controller (Kubernetes NGINX)
  nginxIngressUrl=https://kubernetes.github.io/ingress-nginx
  log-info "Deploying the NGINX Ingress Controller from $nginxIngressUrl..."

  # Deploy the ngnix ingress controller
  kubectl create namespace $ingress_ns

  # Add the ingress-nginx repository
  helm repo add $ingress_helm_repo $nginxIngressUrl

  # Use Helm to deploy an NGINX ingress controller
  helm install $ingress_service_proposed_name $ingress_helm_repo/$ingress_helm_repo \
      --namespace $ingress_ns \
      --set rbac.create=true \
      --set controller.ingressClass=nginx-ingress-dev \
      --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
      --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
      --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux

  log-info "Deploying AKS Cluster Resource Quotas..."
  kubectl apply -f $K8S/k8s-resource-quotas-dev.yaml

fi

#########################################################################################
log-info "Validating AKS Infrastructure Helm Releases"
helm ls --namespace --all-namespaces

#########################################################################################
# Collecting output variable from deployment/existing deployment.

# Obtain the load balancer ip address and assign a domain name
until export INGRESS_LOAD_BALANCER_IP=$(kubectl get services/$ingress_service_fdqn -n $ingress_ns -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2> /dev/null) && test -n "$INGRESS_LOAD_BALANCER_IP"; do echo "Waiting for load balancer deployment" && sleep 20; done
log-verbose "INGRESS_LOAD_BALANCER_IP is: $INGRESS_LOAD_BALANCER_IP"

## This is not optimal as we have hardcoded how we obtain the resource id
## This does NOT work as az network public-ip do not seem to be listed unless a FQDN has been assigned???
export INGRESS_LOAD_BALANCER_IP_ID=$(MSYS_NO_PATHCONV=1 az network lb list --query="[0].frontendIpConfigurations[1].publicIpAddress.id" --output tsv)
log-verbose "INGRESS_LOAD_BALANCER_IP_ID is: $INGRESS_LOAD_BALANCER_IP_ID"
## export INGRESS_LOAD_BALANCER_IP_ID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$INGRESS_LOAD_BALANCER_IP')].[id]" --output tsv)

export EXTERNAL_INGEST_DNS_NAME="${RESOURCE_GROUP}-ingest-dev"
log-verbose "EXTERNAL_INGEST_DNS_NAME is: $EXTERNAL_INGEST_DNS_NAME"

export EXTERNAL_INGEST_FQDN=$(MSYS_NO_PATHCONV=1 az network public-ip update --ids $INGRESS_LOAD_BALANCER_IP_ID --dns-name $EXTERNAL_INGEST_DNS_NAME --query "dnsSettings.fqdn" --output tsv)
log-verbose "EXTERNAL_INGEST_FQDN is: $EXTERNAL_INGEST_FQDN"

tlsfilename=ingestion-ingress-tls

log-warning "Generating the TLS certificate/key pair for FQDN: $EXTERNAL_INGEST_FQDN - Cert File: $tlsfilename.crt"
MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -out $tlsfilename.crt \
  -keyout $tlsfilename.key \
  -subj "/CN=${EXTERNAL_INGEST_FQDN}/O=fabrikam"

#########################################################################################
# Deploying App to AKS cluster

execdir=$(dirname "${BASH_SOURCE[0]}")
version=0.1.0
env=dev
rootpath=/c/users/gillese/training/microservices/microservices-reference-implementation
tlsfilenamefullpath=$rootpath/$tlsfilename
appns=backend-$env

if [ $SKIPAPPDEPLOYMENT == "true" ];then
  log-info "SKIP: Building & Deploying Application to Infrastructure: v$version"
else
  log-info "Building & Deploying Application to Infrastructure: v$version"

  # figure out which directory we are in and call sub scripts with its arguments.
  pushd $execdir >/dev/null
  ./deploy-delivery-service.sh \
    -s $SUBSCRIPTIONID \
    -l $LOCATION \
    -r $RESOURCE_GROUP \
    -k $SSH_PUBLIC_KEY_FILE \
    -p $rootpath \
    -d $DEV_DEPLOYMENT_NAME \
    -a $ACR_SERVER \
    -v $version \
    -e $env \
    -t $tlsfilenamefullpath.key \
    -w $tlsfilenamefullpath.crt \
    -i $IDENTITIES_DEPLOYMENT_NAME \
    -b $DELIVERY_ID_NAME \
    -n $AI_IKEY \
    -f $EXTERNAL_INGEST_FQDN
  popd >/dev/null

  pushd $execdir >/dev/null
  ./deploy-package-service.sh \
    -s $SUBSCRIPTIONID \
    -l $LOCATION \
    -r $RESOURCE_GROUP \
    -k $SSH_PUBLIC_KEY_FILE \
    -p $rootpath \
    -d $DEV_DEPLOYMENT_NAME \
    -a $ACR_SERVER \
    -v $version \
    -e $env \
    -t $tlsfilenamefullpath.key \
    -w $tlsfilenamefullpath.crt \
    -i $IDENTITIES_DEPLOYMENT_NAME \
    -b "" \
    -n $AI_IKEY \
    -f $EXTERNAL_INGEST_FQDN 
  popd >/dev/null

  pushd $execdir >/dev/null
  ./deploy-workflow-service.sh \
    -s $SUBSCRIPTIONID \
    -l $LOCATION \
    -r $RESOURCE_GROUP \
    -k $SSH_PUBLIC_KEY_FILE \
    -p $rootpath \
    -d $DEV_DEPLOYMENT_NAME \
    -a $ACR_SERVER \
    -v $version \
    -e $env \
    -t $tlsfilenamefullpath.key \
    -w $tlsfilenamefullpath.crt \
    -i $IDENTITIES_DEPLOYMENT_NAME \
    -b $WORKFLOW_ID_NAME \
    -n $AI_IKEY \
    -f $EXTERNAL_INGEST_FQDN   
  popd >/dev/null

  pushd $execdir >/dev/null
  ./deploy-ingestion-service.sh \
    -s $SUBSCRIPTIONID \
    -l $LOCATION \
    -r $RESOURCE_GROUP \
    -k $SSH_PUBLIC_KEY_FILE \
    -p $rootpath \
    -d $DEV_DEPLOYMENT_NAME \
    -a $ACR_SERVER \
    -v $version \
    -e $env \
    -t $tlsfilenamefullpath.key \
    -w $tlsfilenamefullpath.crt \
    -i $IDENTITIES_DEPLOYMENT_NAME \
    -b "" \
    -n $AI_IKEY \
    -f $EXTERNAL_INGEST_FQDN    
  popd >/dev/null

  pushd $execdir >/dev/null
  ./deploy-scheduler-service.sh \
    -s $SUBSCRIPTIONID \
    -l $LOCATION \
    -r $RESOURCE_GROUP \
    -k $SSH_PUBLIC_KEY_FILE \
    -p $rootpath \
    -d $DEV_DEPLOYMENT_NAME \
    -a $ACR_SERVER \
    -v $version \
    -e $env \
    -t $tlsfilenamefullpath.key \
    -w $tlsfilenamefullpath.crt \
    -i $IDENTITIES_DEPLOYMENT_NAME \
    -b $DRONESCHEDULER_ID_NAME \
    -n $AI_IKEY \
    -f $EXTERNAL_INGEST_FQDN 
  popd >/dev/null

fi

#########################################################################################
log-info "Controlling Application Helm Releases"
helm ls --namespace $appns

log-info "Controlling K8s Control Plane registered Events"
kubectl get events -n $appns

#########################################################################################
log-warning "DEPLOYMENT: COMPLETE"


echo $'\n'

#########################################################################################
log-warning "Validating Application Deployment"
echo $'\n'

curl -X POST "https://$EXTERNAL_INGEST_FQDN/0.1.0/api/deliveryrequests" --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
   "confirmationRequired": "None",
   "deadline": "",
   "dropOffLocation": "drop off",
   "expedited": true,
   "ownerId": "myowner",
   "packageInfo": {
     "packageId": "mypackage",
     "size": "Small",
     "tag": "mytag",
     "weight": 10
   },
   "pickupLocation": "my pickup",
   "pickupTime": "2019-05-08T20:00:00.000Z"
 }' > deliveryresponse.json


DELIVERY_ID=$(cat deliveryresponse.json | jq -r .deliveryId)
curl "https://$EXTERNAL_INGEST_FQDN/api/deliveries/$DELIVERY_ID" --header 'Accept: application/json' -k
