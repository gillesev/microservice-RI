## -------------------
# Azure Infrastructure
## -------------------

run command:

s: Azure Subscription
l: Azure Region
r: Resource Group
k: SSH public key file
i: Skip Infrastructure deployment
j: Existing Deployment Id
m: Skip Client Tooling Install
n: Skip AKS Infrastructure deployment
o: Skip Application deployment

## Example 1
## Deploy Azure infrastructure and application
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -m "true" -o "true"

## Example 2
## Deploy application onto existing Azure infrastructure
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -i "true" -j "1620846576357967700" -m "true" -n "true"

# Check deployment status

az deployment group show --name "azuredeploy-1620920099406551000-dev" -g "geaz-msri-rg2" --query "properties.provisioningState" -o tsv

## ---------------
# Test Application
## ---------------

curl -X POST "https://geaz-msri-rg2-ingest-dev.eastus2.cloudapp.azure.com/0.1.0/api/deliveryrequests" --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
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
 }'

curl "https://geaz-msri-rg2-ingest-dev.eastus2.cloudapp.azure.com/0.1.0/api/deliveries/$DELIVERY_ID" --header 'Accept: application/json' -k

## Trouble-shoot Kubernetes Network issues
## Check DNS resolution for a pod
## pod ID: package-v010-dev-7dc5676448-s4gfs
## DNS name (guessed): package-010
kubectl exec -i -t package-v010-dev-7dc5676448-s4gfs --namespace backend-dev -- nslookup package-010

This led to replacing (for now) the workflow project's deploy helm values.yaml file to include the -010 ($appVersion)
  delivery: http://delivery-010/api/Deliveries/
  drone: http://dronescheduler-010/api/DroneDeliveries/
  package: http://package-010/api/packages/

Probably we should add an ingress rule to rewrite http://delivery/api/deliveries/ to http://delivery-010/api/deliveries???
what is best practise here???
I am still not clear on why we need internal ingress rules for delivery, package and dronescheduler services???

## Clean-up resources
az group delete -n geaz-msri-rg2 --yes --no-wait
az group delete -n geaz-msri-rg2-acr --yes --no-wait

## ---------------------------------
# Deploy Azure DevOps Infrastructure
## ---------------------------------

run command:

d: ADO Organization Name
e: ADO Project Name
s: Subscription
r: GitHub Repo URL
t: GitHub PAT

## Example 1
## YOU MUST replace -t parameter with a valid GitHub Personal Access Token
## DO NOT commit a PAT in GitHub

./inner-loop-scripts/shell/deploy-devops-infrastructure.sh -d "gillesev" -e "MicroService-RI" -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -r "https://github.com/gillesev/microservice-RI.git" -t "GitHub PAT"

## ----------------------------------
# Deploy Azure Devops Group Variables
## ----------------------------------

run command:

d: ADO Organization Name
e: ADO Project Name
s: Subscription
t: Variables

## Example 1
./inner-loop-scripts/shell/deploy-devops-env-variables.sh -d "gillesev" -e "MicroService-RI" -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -t "ACR_SERVER=xxxxxxxx.azurecr.io ACR_NAME=xxxxxxxx"

## ----------------------------------------------
# Deploy Application Azure Devops CI/CD Pipelines
## ----------------------------------------------

## ONLY package service is done.
pre-requisites:
provision ADO Personal Access Token: https://dev.azure.com/gillesev/_usersSettings/tokens

run command:

d: ADO Organization Name
e: ADO Project Name
r: GitHub Repo URL
s: Subscription
g: Resource Group
t: ADO User Email
u: ADO Personal Access Token (PAT)

./inner-loop-scripts/shell/deploy-devops-package-ci-cd.sh -d "gillesev" -e "MicroService-RI" -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -r "https://github.com/gillesev/microservice-RI" -t "ADO User's email" -u "ADO PAT"

### Lessons learned

*install-drone-demo-dev.sh script: deploys the Azure infrastructure (only dev but could deploy infrastructure /per target environment)

*deploy-devops-infrastructure.sh: deploys the Azure DevOps infrastructure

*deploy-devops-env-variables.sh: deploys variable groups used across pipelines (not target deployment specific) used by CI pipelines

*deploy-devops-package-ci-cd.sh: deploys 1 service (e.g. 'package') CI and CD pipelines.
If some CD pipeline variables (azure-pipelines-cd.json file) are using Azure infrastructure guids then this script will replace the place-holder values with the real values and commit/push the azure-pipelines-cd.json file changes.
All other target deployment specific variables should be defined using variable groups and referenced in the azure-pipelines.yml and azure-pipelines-cd.json files.
The CD pipeline executes without runtime parameters and executes in 'stages' that correspond 1-to-1 to target deployments.

