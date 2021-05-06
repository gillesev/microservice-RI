#!/bin/bash

function print_help { echo $'Usage\n\n' \
                           $'-s Subscription\n' \
                           $'-l Location\n' \
                           $'-r Resource Group\n' \
                           $'-k Ssh pubic key filename\n' \
                           $'-? Show Usage' \
                           >&2;
                    }

while getopts s:l:r:k:? option
do
case "${option}"
in
s) SUBSCRIPTION=${OPTARG};;
l) LOCATION=${OPTARG};;
r) RESOURCEGROUP=${OPTARG};;
k) SSHPUBKEYFILENAME=${OPTARG};;
?) print_help; exit 0;;
esac
done

if [[ -z "$SUBSCRIPTION" || -z "$LOCATION" || -z "$RESOURCEGROUP" || -z "$SSHPUBKEYFILENAME" ]]; then
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

#########################################################################################
echo "Purging previous deployment"
az keyvault list-deleted --query "[].{name: name}" -o tsv
az keyvault purge --name dev-wf-nopqttanbbbi2
az keyvault purge --name dev-ds-nopqttanbbbi2
az keyvault purge --name dev-d-nopqttanbbbi2

#########################################################################################

export DEPLOYMENT_SUFFIX=$(date +%s%N)
export PROJECT_ROOT=./
export K8S=$PROJECT_ROOT/k8s
export HELM_CHARTS=$PROJECT_ROOT/charts

export SP_DETAILS=$(az ad sp create-for-rbac --role="Contributor" -o json) && \
export SP_APP_ID=$(echo $SP_DETAILS | jq ".appId" -r) && \
export SP_CLIENT_SECRET=$(echo $SP_DETAILS | jq ".password" -r) && \
export SP_OBJECT_ID=$(az ad sp show --id $SP_APP_ID -o tsv --query objectId)

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################

# Deploy the resource groups and managed identities
# These are deployed first in a separate template to avoid propagation delays with AAD
echo "Deploying Azure Infrastructure Pre-requisites - $DEV_PREREQ_DEPLOYMENT_NAME..."

export DEV_PREREQ_DEPLOYMENT_NAME=azuredeploy-prereqs-${DEPLOYMENT_SUFFIX}-dev

az deployment sub create \
    --name $DEV_PREREQ_DEPLOYMENT_NAME \
    --location $LOCATION \
    --template-file ${PROJECT_ROOT}/azuredeploy-prereqs.json \
    --parameters resourceGroupName=$RESOURCE_GROUP \
                resourceGroupLocation=$LOCATION \
                environmentName=dev || sleep 15;

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
echo "Validating Deployment - $DEV_PREREQ_DEPLOYMENT_NAME..."

deploy_status=$(az deployment sub show --name $DEV_PREREQ_DEPLOYMENT_NAME --query "properties.provisioningState" -o tsv)

if [ $deploy_status ==  "Succeeded" ]
then
  echo "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME succeeded"
else
  echo "Deployment - $DEV_PREREQ_DEPLOYMENT_NAME failed"
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
export DEV_DEPLOYMENT_NAME=azuredeploy-${DEPLOYMENT_SUFFIX}-dev
echo "Deploying Azure Core Infrastructure - $DEV_DEPLOYMENT_NAME..."

# Export the kubernetes cluster version
export KUBERNETES_VERSION=$(az aks get-versions -l $LOCATION --query "orchestrators[?default!=null].orchestratorVersion" -o tsv)

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

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

#########################################################################################
echo "Validating Deployment - $DEV_DEPLOYMENT_NAME..."

deploy_status=$(az deployment group show --name $DEV_DEPLOYMENT_NAME -g $RESOURCE_GROUP --query "properties.provisioningState" -o tsv)

if [ $deploy_status ==  "Succeeded" ]
then
  echo "Deployment - $DEV_DEPLOYMENT_NAME succeeded"
else
  echo "Deployment - $DEV_DEPLOYMENT_NAME failed"
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

echo "Outputs for Deployment - $DEV_DEPLOYMENT_NAME"
echo "ACR Name: $ACR_NAME"
echo "ACR Server: $ACR_SERVER"
echo "AKS Cluster Name: $CLUSTER_NAME"
echo "Key Vault (Delivery) URI: $deliveryKeyVaultUri"
echo "Key Vault (Drone Scheduler) URI: $droneSchedulerKeyVaultUri"
echo "Key Vault (Workflow) Name: $workflowKeyVaultName"
echo "ACR Deployment Name: $acrDeploymentName"
echo "APP INSIGHTS Name: $appInsightsName"

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
echo "Installing kubectl..."

#  Install kubectl
az aks install-cli

# Get the Kubernetes cluster credentials
az aks get-credentials --resource-group=$RESOURCE_GROUP --name=$CLUSTER_NAME --overwrite-existing --admin

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Create namespaces
kubectl create namespace backend-dev

#########################################################################################
echo "Installing Helm..."
choco install kubernetes-helm

#########################################################################################
echo "Configuring RBAC for Application Insights..."

# Acquire Instrumentation Key
export AI_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.appInsightsName.value -o tsv)
export AI_IKEY=$(az resource show \
                    -g $RESOURCE_GROUP \
                    -n $AI_NAME \
                    --resource-type "Microsoft.Insights/components" \
                    --query properties.InstrumentationKey \
                    -o tsv)

# add RBAC for AppInsights
kubectl apply -f $K8S/k8s-rbac-ai.yaml

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
echo "Deploying & Configuring AAD POD Identity..."
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az provider register -n Microsoft.ContainerService

# setup AAD pod identity
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install aad-pod-identity aad-pod-identity/aad-pod-identity

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
nginxIngressUrl=https://kubernetes.github.io/ingress-nginx
echo "Deploying the NGINX Ingress Controller from $nginxIngressUrl..."
ingress_ns=ingress-controllers
ingress_helm_repo=ingress-nginx
ingress_service_proposed_name="nginx-ingress-dev"
ingress_service_fdqn="$ingress_service_proposed_name-$ingress_helm_repo-controller"

# Deploy the ngnix ingress controller
kubectl create namespace $ingress_ns

# Add the ingress-nginx repository
helm repo add $ingress_helm_repo $nginxIngressUrl

# Use Helm to deploy an NGINX ingress controller
helm install $ingress_service_proposed_name $ingress_helm_repo/$ingress_helm_repo \
    --namespace $ingress_ns \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Obtain the load balancer ip address and assign a domain name
until export INGRESS_LOAD_BALANCER_IP=$(kubectl get services/$ingress_service_fdqn -n $ingress_ns -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2> /dev/null) && test -n "$INGRESS_LOAD_BALANCER_IP"; do echo "Waiting for load balancer deployment" && sleep 20; done
echo "INGRESS_LOAD_BALANCER_IP is: $INGRESS_LOAD_BALANCER_IP"

## This is not optimal as we have hardcoded how we obtain the resource id
## This does NOT work as az network public-ip do not seem to be listed unless a FQDN has been assigned???
export INGRESS_LOAD_BALANCER_IP_ID=$(az network lb list --query="[0].frontendIpConfigurations[1].publicIpAddress.id" --output tsv)
echo "INGRESS_LOAD_BALANCER_IP_ID is: $INGRESS_LOAD_BALANCER_IP_ID"
## export INGRESS_LOAD_BALANCER_IP_ID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$INGRESS_LOAD_BALANCER_IP')].[id]" --output tsv)

export EXTERNAL_INGEST_DNS_NAME="${RESOURCE_GROUP}-ingest-dev"
echo "EXTERNAL_INGEST_DNS_NAME is: $EXTERNAL_INGEST_DNS_NAME"

## we MUST use MSYS_NO_PATHCONV=1 here as the $INGRESS_LOAD_BALANCER_IP_ID represents a resource id with some / segements which will be
## interpreted as a path
export EXTERNAL_INGEST_FQDN=$(MSYS_NO_PATHCONV=1 az network public-ip update --ids $INGRESS_LOAD_BALANCER_IP_ID --dns-name $EXTERNAL_INGEST_DNS_NAME --query "dnsSettings.fqdn" --output tsv)
echo "EXTERNAL_INGEST_FQDN is: $EXTERNAL_INGEST_FQDN"

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# checking if EXTERNAL_INGEST_FQDN exists
if [ -n $EXTERNAL_INGEST_FQDN ]
then
  echo "EXTERNAL_INGEST_FQDN is defined...continuing..."
else
  echo "Cannot retrieve EXTERNAL_INGEST_FQDN"
  exit 1
fi

#########################################################################################
echo "Generating the TLS certificate/key pair for FQDN: $EXTERNAL_INGEST_FQDN..."
if [ -f "ingestion-ingress-tls.crt" ]; then
    echo "ingestion-ingress-tls.crt exists."
else
    MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -out ingestion-ingress-tls.crt \
    -keyout ingestion-ingress-tls.key \
    -subj "/CN=${EXTERNAL_INGEST_FQDN}/O=fabrikam"
fi

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
echo "Deploying AKS Cluster Resource Quotas..."
kubectl apply -f $K8S/k8s-resource-quotas-dev.yaml

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

#########################################################################################
echo "Deploying Shipping Delivery Service..."

export COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryCosmosDbName.value -o tsv)
export DATABASE_NAME="${COSMOSDB_NAME}-db"
export COLLECTION_NAME="${DATABASE_NAME}-col"
export DELIVERY_KEYVAULT_URI=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.deliveryKeyVaultUri.value -o tsv)

export DELIVERY_PATH=$PROJECT_ROOT/src/shipping/delivery

# Build the Docker image
docker build --pull --compress -t $ACR_SERVER/delivery:0.1.0 $DELIVERY_PATH/.

# Push the image to ACR
az acr login --name $ACR_NAME
docker push $ACR_SERVER/delivery:0.1.0

# Extract pod identity outputs from deployment
export DELIVERY_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.deliveryPrincipalResourceId.value -o tsv)
export DELIVERY_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $DELIVERY_ID_NAME --query clientId -o tsv)
export DELIVERY_INGRESS_TLS_SECRET_NAME=delivery-ingress-tls

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Deploy the service

# WARNING: could not make helm v3 dependencies work, so shortcut for now is:
# Update the helm dependencies even though we took the values from charts\delivery\envs\delivery-dev\values.yaml
# and copied them in charts\delivery\values.yaml
# This command should create the Chart.lock file and should create the ./charts directory under charts\delivery
MSYS_NO_PATHCONV=1 helm dependency update $HELM_CHARTS/delivery/

# This will install the chart templates
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
read -p "Pausing Deployment..."

#########################################################################################
echo "Deploying Shipping Package micro-service..."

export COSMOSDB_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.packageMongoDbName.value -o tsv)

export PACKAGE_PATH=$PROJECT_ROOT/src/shipping/package

# Build the docker image
docker build -f $PACKAGE_PATH/Dockerfile -t $ACR_SERVER/package:0.1.0 $PACKAGE_PATH

# Push the docker image to ACR
az acr login --name $ACR_NAME
docker push $ACR_SERVER/package:0.1.0

# Create secret
# Note: Connection strings cannot be exported as outputs in ARM deployments
export COSMOSDB_CONNECTION=$(az cosmosdb list-connection-strings --name $COSMOSDB_NAME --resource-group $RESOURCE_GROUP --query "connectionStrings[0].connectionString" -o tsv | sed 's/==/%3D%3D/g')
export COSMOSDB_COL_NAME=packages

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Deploy service
helm install $HELM_CHARTS/package/ \
     --set image.tag=0.1.0 \
     --set image.repository=package \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=package \
     --set ingress.hosts[0].tls=false \
     --set secrets.appinsights.ikey=$AI_IKEY \
     --set secrets.mongo.pwd=$COSMOSDB_CONNECTION \
     --set cosmosDb.collectionName=$COSMOSDB_COL_NAME \
     --set dockerregistry=$ACR_SERVER \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name package-v0.1.0-dev \
     --dep-up

#########################################################################################
echo "Deploying Shipping Workflow micro-service..."

export WORKFLOW_KEYVAULT_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.workflowKeyVaultName.value -o tsv)
export WORKFLOW_PATH=$PROJECT_ROOT/src/shipping/workflow

# Build the Docker image
docker build --pull --compress -t $ACR_SERVER/workflow:0.1.0 $WORKFLOW_PATH/.

# Push the image to ACR
az acr login --name $ACR_NAME
docker push $ACR_SERVER/workflow:0.1.0

# Extract outputs from deployment
export WORKFLOW_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.workflowPrincipalResourceId.value -o tsv)
export WORKFLOW_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $WORKFLOW_ID_NAME --query clientId -o tsv)

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Deploy the service
helm install $HELM_CHARTS/workflow/ \
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
     --namespace backend-dev \
     --name workflow-v0.1.0-dev \
     --dep-up

#########################################################################################
echo "Deploying Shipping Ingestion micro-service..."

export INGESTION_QUEUE_NAMESPACE=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionQueueNamespace.value -o tsv)
export INGESTION_QUEUE_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionQueueName.value -o tsv)
export INGESTION_ACCESS_KEY_NAME=$(az deployment group show -g $RESOURCE_GROUP -n $DEV_DEPLOYMENT_NAME --query properties.outputs.ingestionServiceAccessKeyName.value -o tsv)
export INGESTION_ACCESS_KEY_VALUE=$(az servicebus namespace authorization-rule keys list --resource-group $RESOURCE_GROUP --namespace-name $INGESTION_QUEUE_NAMESPACE --name $INGESTION_ACCESS_KEY_NAME --query primaryKey -o tsv)

export INGESTION_PATH=$PROJECT_ROOT/src/shipping/ingestion

# Build the docker image
docker build -f $INGESTION_PATH/Dockerfile -t $ACR_SERVER/ingestion:0.1.0 $INGESTION_PATH

# Push the docker image to ACR
az acr login --name $ACR_NAME
docker push $ACR_SERVER/ingestion:0.1.0

# Set secreat name
export INGRESS_TLS_SECRET_NAME=ingestion-ingress-tls

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Deploy service
helm install $HELM_CHARTS/ingestion/ \
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
     --set secrets.queue.keyname=IngestionServiceAccessKey \
     --set secrets.queue.keyvalue=${INGESTION_ACCESS_KEY_VALUE} \
     --set secrets.queue.name=${INGESTION_QUEUE_NAME} \
     --set secrets.queue.namespace=${INGESTION_QUEUE_NAMESPACE} \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name ingestion-v0.1.0-dev \
     --dep-up

#########################################################################################
echo "Deploying Shipping Drone Scheduler micro-service..."

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
docker build -f $DRONE_PATH/Dockerfile -t $ACR_SERVER/dronescheduler:0.1.0 $DRONE_PATH/../

# Push the images to ACR
az acr login --name $ACR_NAME
docker push $ACR_SERVER/dronescheduler:0.1.0

printenv > import-$RESOURCE_GROUP-envs.sh; sed -i -e 's/^/export /' import-$RESOURCE_GROUP-envs.sh

# Deploy the service
helm install $HELM_CHARTS/dronescheduler/ \
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
     --namespace backend-dev \
     --name dronescheduler-v0.1.0-dev \
     --dep-up

#########################################################################################
echo "Validating the Shipping application is running..."

curl -X POST "https://$EXTERNAL_INGEST_FQDN/api/deliveryrequests" --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
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

