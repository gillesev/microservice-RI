export HELM_CHARTS=.//charts
export ACR_SERVER=i77tddxe3v5lw.azurecr.io
export EXTERNAL_INGEST_FQDN=geaz-msri-rg-ingest-dev.eastus2.cloudapp.azure.com
export DELIVERY_INGRESS_TLS_SECRET_NAME=delivery-ingress-tls
export DELIVERY_PRINCIPAL_CLIENT_ID=f9313bfd-fffc-4148-a27b-da3a5969c099
export DELIVERY_PRINCIPAL_RESOURCE_ID=/subscriptions/3759d480-6b3b-4ef6-920e-eb27803ab8e3/resourceGroups/geaz-msri-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dev-d
export DATABASE_NAME=dev-d-nopqttanbbbi2-db
export COLLECTION_NAME=dev-d-nopqttanbbbi2-db-col
export DELIVERY_KEYVAULT_URI=https://dev-d-nopqttanbbbi2.vault.azure.net/
export AI_IKEY=8737d0db-cc6f-4631-b4c6-dbc9fdae0e75

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


delivery deployment error:
--------------------------

command issued:
$ kubectl logs deploy/delivery-v010-dev --namespace backend-dev

Unhandled exception. Microsoft.Azure.Services.AppAuthentication.AzureServiceTokenProviderException: Parameters: Connection String: [No connection string specified], Resource: https://vault.azure.net, Authority: https://login.windows.net/11323e60-239d-49ea-b95e-09aeacca8eb9. Exception Message: Tried the following 3 methods to get an access token, but none of them worked.
Parameters: Connection String: [No connection string specified], Resource: https://vault.azure.net, Authority: https://login.windows.net/11323e60-239d-49ea-b95e-09aeacca8eb9. Exception Message: Tried to get token using Managed Service Identity. Access token could not be acquired. MSI ResponseCode: BadRequest, Response: {"error":"invalid_request","error_description":"Multiple user assigned identities exist, please specify the clientId / resourceId of the identity in the token request"}
Parameters: Connection String: [No connection string specified], Resource: https://vault.azure.net, Authority: https://login.windows.net/11323e60-239d-49ea-b95e-09aeacca8eb9. Exception Message: Tried to get token using Visual Studio. Access token could not be acquired. Environment variable LOCALAPPDATA not set.
Parameters: Connection String: [No connection string specified], Resource: https://vault.azure.net, Authority: https://login.windows.net/11323e60-239d-49ea-b95e-09aeacca8eb9. Exception Message: Tried to get token using Azure CLI. Access token could not be acquired. /bin/bash: az: No such file or directory


   at Microsoft.Azure.Services.AppAuthentication.AzureServiceTokenProvider.GetAccessTokenAsyncImpl(String authority, String resource, String scope)
   at Microsoft.Azure.KeyVault.KeyVaultCredential.PostAuthenticate(HttpResponseMessage response)
   at Microsoft.Azure.KeyVault.KeyVaultCredential.ProcessHttpRequestAsync(HttpRequestMessage request, CancellationToken cancellationToken)
   at Microsoft.Azure.KeyVault.KeyVaultClient.GetSecretsWithHttpMessagesAsync(String vaultBaseUrl, Nullable`1 maxresults, Dictionary`2 customHeaders, CancellationToken cancellationToken)
   at Microsoft.Azure.KeyVault.KeyVaultClientExtensions.GetSecretsAsync(IKeyVaultClient operations, String vaultBaseUrl, Nullable`1 maxresults, CancellationToken cancellationToken)
   at Microsoft.Extensions.Configuration.AzureKeyVault.AzureKeyVaultConfigurationProvider.LoadAsync()
   at Microsoft.Extensions.Configuration.AzureKeyVault.AzureKeyVaultConfigurationProvider.Load()
   at Microsoft.Extensions.Configuration.ConfigurationRoot..ctor(IList`1 providers)
   at Microsoft.Extensions.Configuration.ConfigurationBuilder.Build()
   at Fabrikam.DroneDelivery.DeliveryService.Startup..ctor(IWebHostEnvironment env) in /app/Fabrikam.DroneDelivery.DeliveryService/Startup.cs:line 42
--- End of stack trace from previous location where exception was thrown ---
   at Microsoft.Extensions.DependencyInjection.ActivatorUtilities.ConstructorMatcher.CreateInstance(IServiceProvider provider)
   at Microsoft.Extensions.DependencyInjection.ActivatorUtilities.CreateInstance(IServiceProvider provider, Type instanceType, Object[] parameters)
   at Microsoft.AspNetCore.Hosting.GenericWebHostBuilder.UseStartup(Type startupType, HostBuilderContext context, IServiceCollection services)
   at Microsoft.AspNetCore.Hosting.GenericWebHostBuilder.<>c__DisplayClass12_0.<UseStartup>b__0(HostBuilderContext context, IServiceCollection services)
   at Microsoft.Extensions.Hosting.HostBuilder.CreateServiceProvider()
   at Microsoft.Extensions.Hosting.HostBuilder.Build()
   at Fabrikam.DroneDelivery.DeliveryService.Program.Main(String[] args) in /app/Fabrikam.DroneDelivery.DeliveryService/Program.cs:line 18
/app/run.sh: line 2:     6 Aborted                 (core dumped) dotnet Fabrikam.DroneDelivery.DeliveryService.dll
