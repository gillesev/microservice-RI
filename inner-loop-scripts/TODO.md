# This will provision all Azure resources required by the application

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
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -m "true" -o "true"

## Example 2
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -i "true" -j "1620742935889071300" -m "true" -n "true"

# This will delete all resources associated with resource group azge-msri-rg2
az group delete --name azge-msri-rg2 --yes

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

## Trouble-shoot Network issues
## Check DNS resolution for a pod
## pod ID: package-v010-dev-7dc5676448-s4gfs
## DNS name (guessed): package-010
kubectl exec -i -t package-v010-dev-7dc5676448-s4gfs --namespace backend-dev -- nslookup package-010

This lead to replacing (for now) the workflow project's deploy helm values.yaml file to include the -010 ($appVersion)
  delivery: http://delivery-010/api/Deliveries/
  drone: http://dronescheduler-010/api/DroneDeliveries/
  package: http://package-010/api/packages/

Probably we should add an ingress rule to rewrite http://delivery/api/deliveries/ to http://delivery-010/api/deliveries???
what is best practise here???
I am still not clear on why we need internal ingress rules for delivery, package and dronescheduler services???

## Clean-up resources
az group delete -n geaz-msri-rg2 --yes --no-wait
az group delete -n geaz-msri-rg2-acr --yes --no-wait
