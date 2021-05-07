run command:

s: gillesev subscription
l: azure region as eastus2
r: resource group
k: ssh public key file
i: if you want to skip the infrastructure first 2 initialization phase.
j: the id for an existing deployment

./inner-loop-scripts/shell/install-drone-demo-dev.sh -s "3759d480-6b3b-4ef6-920e-eb27803ab8e3" -l "eastus2" -r "geaz-msri-rg2" -k "C:\Users\gillese\.ssh\id_rsa.pub" -i "true" -j "1620346183023190000"

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