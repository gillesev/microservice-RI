# This will provision all Azure resources requried by the application

run command:

s: Azure Subscription
l: Azure Region
r: Resource Group
k: SSH public key file
i: Skip Infrastructure deployment
j: Existing Deployment Id
m: Skip Client Tooling Install
o: Skip Application deployment

## Example 1
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -m "true" -o "true"

## Example 2
./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -i "true" -j "1620415394549241400" -m "true" -n "true"

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
 }' > deliveryresponse.json

 curl -X POST "https://40.70.229.172/api/deliveryrequests" --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
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