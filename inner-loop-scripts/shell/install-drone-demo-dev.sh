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
                           $'-i Skip Deployment\n' \
                           $'-j Deployment Suffix\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts s:l:r:k:i:j:? option
do
case "${option}"
in
s) SUBSCRIPTION=${OPTARG};;
l) LOCATION=${OPTARG};;
r) RESOURCEGROUP=${OPTARG};;
k) SSHPUBKEYFILENAME=${OPTARG};;
i) SKIPDEPLOYMENT=${OPTARG};;
j) DEPOYSUFFIX=${OPTARG};;
?) print_help; exit 0;;
esac
done

function log-info {
  echo -e "${PURPLE}$1${NOCOLOR}"
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

log-warning "DEPLOYMENT: STARTING"

log-info "Subscription: $SUBSCRIPTION"
log-info "Location: $LOCATION"
log-info "Resource Group: $RESOURCEGROUP"
log-info "SSH Public key file: $SSHPUBKEYFILENAME"
log-info "Skip Infrastructure Deployment: $SKIPDEPLOYMENT"
log-info "Ingrastructure Deployment No: $DEPOYSUFFIX ${NOCOLOR}"

prompt "Press ENTER key to proceed..."

if [[ -z "$SUBSCRIPTION" || -z "$LOCATION" || -z "$RESOURCEGROUP" || -z "$SSHPUBKEYFILENAME" || -z "$SKIPDEPLOYMENT" || -z "$DEPOYSUFFIX" ]]; then
print_help;
exit 2
fi

export SUBSCRIPTIONID=$SUBSCRIPTION
export LOCATION=$LOCATION
export RESOURCE_GROUP=$RESOURCEGROUP

userObjectId=$(az ad signed-in-user show --query objectId -o tsv)

if [ -z "$userObjectId" ];then
   az login > /dev/null
fi

az account set --subscription=$SUBSCRIPTIONID

export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
export TENANT_ID=$(az account show --query tenantId --output tsv)

export SSH_PUBLIC_KEY_FILE=$SSHPUBKEYFILENAME

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
log-info "SKIP: Purging previous deployment"
else
log-info "Purging previous deployment"
az keyvault list-deleted --query "[].{name: name}" -o tsv
az keyvault purge --name dev-wf-nopqttanbbbi2
az keyvault purge --name dev-ds-nopqttanbbbi2
az keyvault purge --name dev-d-nopqttanbbbi2
fi

#########################################################################################
if [ $SKIPDEPLOYMENT == "true" ];then
export DEPLOYMENT_SUFFIX=$DEPOYSUFFIX
else
export DEPLOYMENT_SUFFIX=$(date +%s%N)
fi

#########################################################################################
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
export DEV_PREREQ_DEPLOYMENT_NAME=azuredeploy-prereqs-${DEPLOYMENT_SUFFIX}-dev
if [ $SKIPDEPLOYMENT == "true" ];then
log-info "SKIP: Deploying Azure Infrastructure Pre-requisites - $DEV_PREREQ_DEPLOYMENT_NAME..."
else
log-info "Deploying Azure Infrastructure Pre-requisites - $DEV_PREREQ_DEPLOYMENT_NAME..."

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
  log-info "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME succeeded"
else
  log-error "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME failed"
  exit 1
fi

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

#########################################################################################
export KUBERNETES_VERSION=$(az aks get-versions -l $LOCATION --query "orchestrators[?default!=null].orchestratorVersion" -o tsv)
export DEV_DEPLOYMENT_NAME=azuredeploy-${DEPLOYMENT_SUFFIX}-dev
if [ $SKIPDEPLOYMENT == "true" ];then
log-info "SKIP: Deploying Azure Core Infrastructure - $DEV_DEPLOYMENT_NAME..."
else
log-info "Deploying Azure Core Infrastructure - $DEV_DEPLOYMENT_NAME..."

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

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh
fi
#########################################################################################
echo "Validating Deployment - $DEV_DEPLOYMENT_NAME..."

deploy_status=$(az deployment group show --name $DEV_DEPLOYMENT_NAME -g $RESOURCE_GROUP --query "properties.provisioningState" -o tsv)

if [ $deploy_status ==  "Succeeded" ]
then
  log-info "Deployment - $DEV_DEPLOYMENT_NAME succeeded"
else
  log-error "Deployment - $DEV_DEPLOYMENT_NAME failed"
  exit 1
fi

export ACR_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.acrName.value -o tsv)
export ACR_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
export CLUSTER_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.aksClusterName.value -o tsv)
deliveryKeyVaultUri=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryKeyVaultUri.value -o tsv)
droneSchedulerKeyVaultUri=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
workflowKeyVaultName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.workflowKeyVaultName.value -o tsv)
acrDeploymentName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.acrDeploymentName.value -o tsv)
appInsightsName=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.appInsightsName.value -o tsv)

echo "Outputs for Deployment - $DEV_DEPLOYMENT_NAME\n"
echo "ACR Name: $ACR_NAME"
echo "ACR Server: $ACR_SERVER"
echo "AKS Cluster Name: $CLUSTER_NAME"
echo "Key Vault (Delivery) URI: $deliveryKeyVaultUri"
echo "Key Vault (Drone Scheduler) URI: $droneSchedulerKeyVaultUri"
echo "Key Vault (Workflow) Name: $workflowKeyVaultName"
echo "ACR Deployment Name: $acrDeploymentName"
echo "APP INSIGHTS Name: $appInsightsName"

#########################################################################################
ingress_ns=ingress-controllers
ingress_helm_repo=ingress-nginx
ingress_service_proposed_name="nginx-ingress-dev"
ingress_service_fdqn="$ingress_service_proposed_name-$ingress_helm_repo-controller"

# Acquire Instrumentation Key
export AI_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.appInsightsName.value -o tsv)
export AI_IKEY=$(az resource show \
                    -g $RESOURCE_GROUP \
                    -n $AI_NAME \
                    --resource-type "Microsoft.Insights/components" \
                    --query properties.InstrumentationKey \
                    -o tsv)

if [ $SKIPDEPLOYMENT == "true" ];then
log-info "SKIP: Deploying kubectl/HelmAAD POD Identity/NGINX Ingress Controller/ "
else
log-info "Installing kubectl..."

#  Install kubectl
az aks install-cli

# Get the Kubernetes cluster credentials
az aks get-credentials --resource-group=$RESOURCE_GROUP --name=$CLUSTER_NAME --overwrite-existing --admin

# Create namespaces
kubectl create namespace backend-dev

#########################################################################################
log-info "Installing Helm..."
choco install kubernetes-helm

#########################################################################################
log-info "Configuring RBAC for Application Insights..."
# add RBAC for AppInsights
kubectl apply -f $K8S/k8s-rbac-ai.yaml

#########################################################################################
log-info "Deploying & Configuring AAD POD Identity..."
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az provider register -n Microsoft.ContainerService

# setup AAD pod identity
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm repo update
helm install aad-pod-identity aad-pod-identity/aad-pod-identity --set installCRDs=true --set nmi.allowNetworkPluginKubenet=true  --namespace kube-system

#########################################################################################
secretStoreCSIDriverUri=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
secretStoreCSIDriverHelmRepo=csi-secrets-store-provider-azure
log-info "Deploying the Azure Secrets Store CSI driver provider..."
log-info "Installing Helm chart: $secretStoreCSIDriverUri"

helm repo add $secretStoreCSIDriverHelmRepo $secretStoreCSIDriverUri
helm install csi $secretStoreCSIDriverHelmRepo/$secretStoreCSIDriverHelmRepo

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

fi

#########################################################################################
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

# Obtain the load balancer ip address and assign a domain name
until export INGRESS_LOAD_BALANCER_IP=$(kubectl get services/$ingress_service_fdqn -n $ingress_ns -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2> /dev/null) && test -n "$INGRESS_LOAD_BALANCER_IP"; do echo "Waiting for load balancer deployment" && sleep 20; done
log-info "INGRESS_LOAD_BALANCER_IP is: $INGRESS_LOAD_BALANCER_IP"

## This is not optimal as we have hardcoded how we obtain the resource id
## This does NOT work as az network public-ip do not seem to be listed unless a FQDN has been assigned???
export INGRESS_LOAD_BALANCER_IP_ID=$(MSYS_NO_PATHCONV=1 az network lb list --query="[0].frontendIpConfigurations[1].publicIpAddress.id" --output tsv)
log-info "INGRESS_LOAD_BALANCER_IP_ID is: $INGRESS_LOAD_BALANCER_IP_ID"
## export INGRESS_LOAD_BALANCER_IP_ID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$INGRESS_LOAD_BALANCER_IP')].[id]" --output tsv)

export EXTERNAL_INGEST_DNS_NAME="${RESOURCE_GROUP}-ingest-dev"
log-info "EXTERNAL_INGEST_DNS_NAME is: $EXTERNAL_INGEST_DNS_NAME"

export EXTERNAL_INGEST_FQDN=$(MSYS_NO_PATHCONV=1 az network public-ip update --ids $INGRESS_LOAD_BALANCER_IP_ID --dns-name $EXTERNAL_INGEST_DNS_NAME --query "dnsSettings.fqdn" --output tsv)
log-info "EXTERNAL_INGEST_FQDN is: $EXTERNAL_INGEST_FQDN"

#########################################################################################
log-info "Generating the TLS certificate/key pair for FQDN: $EXTERNAL_INGEST_FQDN..."
if [ -f "ingestion-ingress-tls.crt" ]; then
    log-info "ingestion-ingress-tls.crt exists."
else
    MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -out ingestion-ingress-tls.crt \
    -keyout ingestion-ingress-tls.key \
    -subj "/CN=${EXTERNAL_INGEST_FQDN}/O=fabrikam"
fi

#########################################################################################
if [ $SKIPDEPLOYMENT == "true" ];then
log-info "SKIP: Deploying AKS Cluster Resource Quotas"
else
log-info "Deploying AKS Cluster Resource Quotas..."
kubectl apply -f $K8S/k8s-resource-quotas-dev.yaml
fi

#########################################################################################
log-info "Deploying Shipping Delivery Service..."

export COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryCosmosDbName.value -o tsv)
export DATABASE_NAME="${COSMOSDB_NAME}-db"
export COLLECTION_NAME="${DATABASE_NAME}-col"
export DELIVERY_KEYVAULT_URI=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryKeyVaultUri.value -o tsv)
export DELIVERY_PATH=$PROJECT_ROOT/src/shipping/delivery

# Build the Docker image
log-info "Building the Shipping Delivery Service docker image..."
docker build --pull --compress -t $ACR_SERVER/delivery:0.1.0 $DELIVERY_PATH/.

# Push the image to ACR
log-info "Pushing the Shipping Delivery Service docker image to ACR server: $ACR_SERVER"
az acr login --name $ACR_NAME
docker push $ACR_SERVER/delivery:0.1.0

# Extract pod identity outputs from deployment
export DELIVERY_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.deliveryPrincipalResourceId.value -o tsv)
export DELIVERY_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $DELIVERY_ID_NAME --query clientId -o tsv)
export DELIVERY_INGRESS_TLS_SECRET_NAME=delivery-ingress-tls

# Deploy the service

# WARNING: could not make helm v3 dependencies work, so shortcut for now is:
# Update the helm dependencies even though we took the values from charts\delivery\envs\delivery-dev\values.yaml
# and copied them in charts\delivery\values.yaml
# This command should create the Chart.lock file and should create the ./charts directory under charts\delivery

log-info "Installing the Shipping Delivery Service Helm release: delivery-v0.1.0-dev"
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/delivery/
MSYS_NO_PATHCONV=1 helm install delivery-v0.1.0-dev $HELM_CHARTS/delivery/ \
     --set image.tag=0.1.0 \
     --set image.repository=delivery \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=delivery \
     --set ingress.hosts[0].tls=true \
     --set ingress.hosts[0].tlsSecretName=$DELIVERY_INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].name=$DELIVERY_INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].key="$(cat ingestion-ingress-tls.key)" \
     --set ingress.tls.secrets[0].certificate="$(cat ingestion-ingress-tls.crt)" \
     --set identity.clientid=$DELIVERY_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$DELIVERY_PRINCIPAL_RESOURCE_ID \
     --set cosmosdb.id=$DATABASE_NAME \
     --set cosmosdb.collectionid=$COLLECTION_NAME \
     --set keyvault.uri=$DELIVERY_KEYVAULT_URI \
     --set secrets.appinsights.ikey=$AI_IKEY \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
log-info "Deploying Shipping Package micro-service..."

export COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.packageMongoDbName.value -o tsv)

export PACKAGE_PATH=$PROJECT_ROOT/src/shipping/package

# Build the docker image
log-info "Building the Shipping Package Service docker image..."
docker build -f $PACKAGE_PATH/Dockerfile -t $ACR_SERVER/package:0.1.0 $PACKAGE_PATH

# Push the docker image to ACR
log-info "Pushing the Shipping Package Service docker image to ACR server: $ACR_SERVER"
az acr login --name $ACR_NAME
docker push $ACR_SERVER/package:0.1.0

# Create secret
# Note: Connection strings cannot be exported as outputs in ARM deployments
export COSMOSDB_CONNECTION=$(az cosmosdb list-connection-strings --name $COSMOSDB_NAME --resource-group $RESOURCE_GROUP --query "connectionStrings[0].connectionString" -o tsv | sed 's/==/%3D%3D/g')
export COSMOSDB_COL_NAME=packages

# Deploy service
log-info "Installing the Shipping Package Service Helm release: package-v0.1.0-dev"
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/package/
MSYS_NO_PATHCONV=1 helm install package-v0.1.0-dev $HELM_CHARTS/package/ \
     --set image.tag=0.1.0 \
     --set image.repository=package \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=package \
     --set ingress.hosts[0].tls=false \
     --set secrets.appinsights.ikey=$AI_IKEY \
     --set secrets.mongo.pwd=$COSMOSDB_CONNECTION \
     --set cosmosDb.collectionName=$COSMOSDB_COL_NAME \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev 

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
log-info "Deploying Shipping Workflow micro-service..."

export WORKFLOW_KEYVAULT_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.workflowKeyVaultName.value -o tsv)
export WORKFLOW_PATH=$PROJECT_ROOT/src/shipping/workflow

# Build the Docker image
log-info "Building the Shipping Workflow Service docker image..."
docker build --pull --compress -t $ACR_SERVER/workflow:0.1.0 $WORKFLOW_PATH/.

# Push the image to ACR
log-info "Pushing the Shipping Workflow Service docker image to ACR server: $ACR_SERVER"
az acr login --name $ACR_NAME
docker push $ACR_SERVER/workflow:0.1.0

# Extract outputs from deployment
export WORKFLOW_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.workflowPrincipalResourceId.value -o tsv)
export WORKFLOW_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $WORKFLOW_ID_NAME --query clientId -o tsv)

# Deploy the service
log-info "Installing the Shipping Workflow Service Helm release: workflow-v0.1.0-dev"
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/workflow/
MSYS_NO_PATHCONV=1 helm install workflow-v0.1.0-dev $HELM_CHARTS/workflow/ \
     --set image.tag=0.1.0 \
     --set image.repository=workflow \
     --set dockerregistry=$ACR_SERVER \
     --set identity.clientid=$WORKFLOW_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$WORKFLOW_PRINCIPAL_RESOURCE_ID \
     --set keyvault.name=$WORKFLOW_KEYVAULT_NAME \
     --set keyvault.resourcegroup=$RESOURCE_GROUP \
     --set keyvault.subscriptionid=$SUBSCRIPTION_ID \
     --set keyvault.tenantid=$TENANT_ID \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev 

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
log-info "Deploying Shipping Ingestion micro-service..."

export INGESTION_QUEUE_NAMESPACE=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionQueueNamespace.value -o tsv)
export INGESTION_QUEUE_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionQueueName.value -o tsv)
export INGESTION_ACCESS_KEY_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionServiceAccessKeyName.value -o tsv)
export INGESTION_ACCESS_KEY_VALUE=$(az servicebus namespace authorization-rule keys list --resource-group $RESOURCE_GROUP --namespace-name $INGESTION_QUEUE_NAMESPACE --name $INGESTION_ACCESS_KEY_NAME --query primaryKey -o tsv)

export INGESTION_PATH=$PROJECT_ROOT/src/shipping/ingestion

# Build the docker image
log-info "Building the Shipping Ingestion Service docker image"
docker build -f $INGESTION_PATH/Dockerfile -t $ACR_SERVER/ingestion:0.1.0 $INGESTION_PATH

# Push the docker image to ACR
log-info "Pushing the Shipping Ingestion Service docker image to ACR server: $ACR_SERVER"
az acr login --name $ACR_NAME
docker push $ACR_SERVER/ingestion:0.1.0

# Set secreat name
export INGRESS_TLS_SECRET_NAME=ingestion-ingress-tls

# Deploy service
log-info "Installing the Shipping Ingestion Service Helm release: ingestion-v0.1.0-dev"
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/ingestion/
MSYS_NO_PATHCONV=1 helm install ingestion-v0.1.0-dev $HELM_CHARTS/ingestion/ \
     --set image.tag=0.1.0 \
     --set image.repository=ingestion \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=ingestion \
     --set ingress.hosts[0].tls=true \
     --set ingress.hosts[0].tlsSecretName=$INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].name=$INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].key="$(cat ingestion-ingress-tls.key)" \
     --set ingress.tls.secrets[0].certificate="$(cat ingestion-ingress-tls.crt)" \
     --set secrets.appinsights.ikey=${AI_IKEY} \
     --set secrets.queue.keyname=${INGESTION_ACCESS_KEY_NAME} \
     --set secrets.queue.keyvalue=${INGESTION_ACCESS_KEY_VALUE} \
     --set secrets.queue.name=${INGESTION_QUEUE_NAME} \
     --set secrets.queue.namespace=${INGESTION_QUEUE_NAMESPACE} \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev 

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
log-info "Deploying Shipping Drone Scheduler micro-service..."

export DRONESCHEDULER_KEYVAULT_URI=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
export DRONESCHEDULER_COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerCosmosDbName.value -o tsv)
export ENDPOINT_URL=$(az cosmosdb show -n $DRONESCHEDULER_COSMOSDB_NAME -g $RESOURCE_GROUP --query documentEndpoint -o tsv)
export AUTH_KEY=$(az cosmosdb keys list -n $DRONESCHEDULER_COSMOSDB_NAME -g $RESOURCE_GROUP --query primaryMasterKey -o tsv)
export DATABASE_NAME="invoicing"
export COLLECTION_NAME="utilization"

export DRONE_PATH=$PROJECT_ROOT/src/shipping/dronescheduler

export DRONESCHEDULER_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerPrincipalResourceId.value -o tsv)
export DRONESCHEDULER_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $DRONESCHEDULER_ID_NAME --query clientId -o tsv)

# Build the Docker image
log-info "Building the Shipping Drone Scheduler Service docker image"
docker build -f $DRONE_PATH/Dockerfile -t $ACR_SERVER/dronescheduler:0.1.0 $DRONE_PATH/../

# Push the images to ACR
log-info "Pushing the Shipping Drone Scheduler Service docker image to ACR server: $ACR_SERVER"
az acr login --name $ACR_NAME
docker push $ACR_SERVER/dronescheduler:0.1.0

# Deploy the service
log-info "Installing the Shipping Drone Scheduler Service Helm release: dronescheduler-v0.1.0-dev"
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/dronescheduler/
MSYS_NO_PATHCONV=1 helm install dronescheduler-v0.1.0-dev $HELM_CHARTS/dronescheduler/ \
     --set image.tag=0.1.0 \
     --set image.repository=dronescheduler \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=dronescheduler \
     --set ingress.hosts[0].tls=false \
     --set identity.clientid=$DRONESCHEDULER_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$DRONESCHEDULER_PRINCIPAL_RESOURCE_ID \
     --set keyvault.uri=$DRONESCHEDULER_KEYVAULT_URI \
     --set cosmosdb.id=$DATABASE_NAME \
     --set cosmosdb.collectionid=$COLLECTION_NAME \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev 

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh


#########################################################################################
log-warning "DEPLOYMENT: COMPLETE"

#########################################################################################
log-warning "Validating the Shipping application is running..."

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

