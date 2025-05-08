# Path Rules Azure Application Gateway

## Challenge

~~~mermaid
classDiagram
    AGW <|-- Client
    Storage1 <|-- AGW
    Storage2 <|-- AGW
    class AGW{
    }
    class Client{
    }
    class Storage1{
        container1
        spiderman.txt
    }
    class Storage2{
        container2
        batman.txt
    }
~~~

We do have two Azure Storage accounts which will serve different files. Access to the storage accounts will be done via the Azure Application Gateway. 

Inside the Applicaiton Gateway we will use URL Path Based Routing to route the requests to the correct storage account.

Access directly to the storage accounts:

- storage1: https://cptdagwstorage1.blob.core.windows.net/container1/spiderman.txt
- storage2: https://cptdagwstorage2.blob.core.windows.net/container2/batman.txt

Access via the Application Gateway will look as follows:

- storage1: http://agw.swedencentral.cloudapp.azure.com/container1/spiderman.txt
- storage2: http://agw.swedencentral.cloudapp.azure.com/container1/container2/batman.txt

## Deployment

~~~powershell
az login --use-device-code
az account set -s "sub-cptdx-08" # replace with your subscription name or id
tf init
tf fmt
tf validate
tf plan --out=01.tfplan
tf apply --auto-approve 01.tfplan
~~~

## Test

~~~bash
$prefix = (Get-Content -Path .\terraform.tfvars.json | ConvertFrom-Json).prefix
nslookup cptdagwpr.swedencentral.cloudapp.azure.com # result in my case 9.223.79.0
# directly access the storage accounts
curl https://cptdagwstorage1.blob.core.windows.net/container1/spiderman.txt # 200 ok
curl https://cptdagwstorage2.blob.core.windows.net/container2/batman.txt # 200 ok
# access via the application gateway
curl "http://cptdagwpr.swedencentral.cloudapp.azure.com/container1/spiderman.txt" # 200 ok
curl "http://cptdagwpr.swedencentral.cloudapp.azure.com/container1/container2/batman.txt" # 200 ok
~~~

Get the corresponding logs from the Application Gateway.

~~~powershell
$lawCustomerId=az monitor log-analytics workspace show -g $prefix -n $prefix --query customerId -o tsv
$query="AGWAccessLogs | where OriginalRequestUriWithArgs contains 'batman' or OriginalRequestUriWithArgs contains 'spiderman' | project OriginalRequestUriWithArgs,RequestUri, HttpStatus"
az monitor log-analytics query -w $lawCustomerId --analytics-query $query -o table
~~~

HttpStatus    OriginalRequestUriWithArgs         RequestUri                 TableName
------------  ---------------------------------  -------------------------  -------------
200           /container1/spiderman.txt          /container1/spiderman.txt  PrimaryResult
200           /container1/container2/batman.txt  /container2/batman.txt     PrimaryResult

Get the corresponding logs from the Storage Accounts.

~~~powershell
$queryStorage="StorageBlobLogs | where TimeGenerated > ago(10m) | where ObjectKey contains 'batman' or ObjectKey contains 'spiderman'| where StatusCode == '200'| project AccountName, Uri, StatusCode, CallerIpAddress"
az monitor log-analytics query -w $lawCustomerId --analytics-query $queryStorage -o table
~~~

AccountName      CallerIpAddress      StatusCode    TableName      Uri
---------------  -------------------  ------------  -------------  --------------------------------------------------------------------------
cptdagwstorage1  10.0.0.6:22632       200           PrimaryResult  https://cptdagwstorage1.blob.core.windows.net:443/container1/spiderman.txt
cptdagwstorage1  172.201.77.43:24151  200           PrimaryResult  https://cptdagwstorage1.blob.core.windows.net:443/container1/spiderman.txt
cptdagwstorage2  10.0.0.4:30264       200           PrimaryResult  https://cptdagwstorage2.blob.core.windows.net:443/container2/batman.txt
cptdagwstorage2  20.107.5.167:57940   200           PrimaryResult  https://cptdagwstorage2.blob.core.windows.net:443/container2/batman.txt

## cleanup

~~~powershell
tf destroy --auto-approve
~~~

## Misc

### How to find the diagnostic settings log categories for a resource

Find all diagnostic settings log categories for a resource: https://learn.microsoft.com/en-us/azure/azure-monitor/reference/logs-index