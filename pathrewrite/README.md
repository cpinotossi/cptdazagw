# Path Rules Azure Application Gateway

## Introduction

We do have two Azure Storage accounts which will serve different files. Access to the storage accounts will be done via the Azure Application Gateway.

Inside the Applicaiton Gateway we will use URL Path Based Routing to route the requests to the correct storage account.

Access directly to the storage accounts:

- storage1: https://cptdagwstorage1.blob.core.windows.net/container1/spiderman.txt
- storage2: https://cptdagwstorage2.blob.core.windows.net/container2/batman.txt

Access via the Application Gateway will look as follows:

- storage1: http://agw.swedencentral.cloudapp.azure.com/app1/container1/spiderman.txt
- storage2: http://agw.swedencentral.cloudapp.azure.com/app2/container1/batman.txt

~~~mermaid
flowchart TD
    subgraph Client
        A[Client Request]
    end

    subgraph AGW[Azure Application Gateway]
        decision{Path<br>Component?}
    end

    subgraph Storage1["Storage Account 1 (cptdagwstorage1)"]
        S1[container1/spiderman.txt]
    end

    subgraph Storage2["Storage Account 2 (cptdagwstorage2)"]
        S2[container2/batman.txt]
    end

    A --> AGW
    AGW --> decision
    decision -- "/app1/*" --> S1
    decision -- "/app2/*" --> S2
~~~

- The Application Gateway inspects the first path component (`app1` or `app2`) of each incoming request.
- Based on this, it routes the request to the correct backend storage account.
- All requests use the same FQDN for the Application Gateway; the path determines the backend.
- The Application Gateway will strip out the first path component (`app1` or `app2`) before forwarding the request to the storage account.


## Deployment

~~~powershell
cd pathrewrite
az login --use-device-code
az account set -s "sub-cptdx-08" # replace with your subscription name or id
tf init
tf fmt
tf validate
tf plan --out=01.tfplan
tf apply --auto-approve 01.tfplan
~~~

## How the rewrite Rule works

The Application Gateway implements a path rewrite mechanism that allows clients to access different storage accounts using clean, application-specific paths ("/app1", "/app2") while translating them to the actual backend paths. This is particularly useful for microservices architecture where you want to expose clean public APIs while routing to different backend services.

### Backend Configuration

Backend Address Pools
Purpose: Defines two backend pools pointing to different Azure Storage accounts:

~~~hcl
backend_address_pool {
  fqdns = ["${var.storage_account_name_1}.blob.core.windows.net"]
  name  = "storage1"
}
backend_address_pool {
  fqdns = ["${var.storage_account_name_2}.blob.core.windows.net"]
  name  = "storage2"
}
~~~

- storage1: Points to cptdagwstorage1.blob.core.windows.net
- storage2: Points to cptdagwstorage2.blob.core.windows.net

Backend HTTP Settings

~~~hcl
backend_http_settings {
  name                                = "storage1"
  cookie_based_affinity               = "Disabled"
  pick_host_name_from_backend_address = true
  port                                = 443
  protocol                            = "Https"
  request_timeout                     = 20
  probe_name                          = "storage1"
}
~~~

Key Setting: pick_host_name_from_backend_address = true ensures the Application Gateway uses the storage account's FQDN as the HTTP Host header when forwarding requests.

### Request Routing Configuration

HTTP Listener

~~~hcl
http_listener {
  frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
  frontend_port_name             = "port_80"
  host_name                      = ""
  host_names                     = ["${var.prefix}.swedencentral.cloudapp.azure.com"]
  name                           = "public"
  protocol                       = "Http"
}
~~~

Purpose: Listens for incoming HTTP requests on port 80 for the specific hostname.

> NOTE: We make use of port 80 and therefore of HTTP instead of HTTPS. This is just for the sake of simplicity. In a production environment, you would typically use HTTPS.

Request Routing Rule

~~~hcl
request_routing_rule {
  backend_address_pool_name  = "storage1"
  backend_http_settings_name = "storage1"
  http_listener_name         = "public"
  name                       = "storage1"
  priority                   = 2
  rule_type                  = "PathBasedRouting"
  url_path_map_name          = var.prefix
}
~~~

Key Point: rule_type = "PathBasedRouting" enables path-based routing, which directs requests to different backends based on the URL path.

### URL Path Map - The Core Routing Logic

~~~hcl
url_path_map {
  name                               = var.prefix
  default_backend_address_pool_name  = "storage1"
  default_backend_http_settings_name = "storage1"
  
  path_rule {
    name                       = "app1"
    paths                      = ["/app1/*"]
    backend_address_pool_name  = "storage1"
    backend_http_settings_name = "storage1"
    rewrite_rule_set_name      = "app1"
  }
  
  path_rule {
    name                       = "app2"
    paths                      = ["/app2/*"]
    backend_address_pool_name  = "storage2"
    backend_http_settings_name = "storage2"
    rewrite_rule_set_name      = "app2"
  }
}
~~~

How It Works:
Default Route: Any request not matching specific paths goes to storage1
App1 Route: Requests to /app1/* go to storage1 with app1 rewrite rules
App2 Route: Requests to /app2/* go to storage2 with app2 rewrite rules

### Rewrite Rule Sets - The Path Transformation Magic

App1 Rewrite Rule

~~~hcl
url_path_map {
  name                               = var.prefix
  default_backend_address_pool_name  = "storage1"
  default_backend_http_settings_name = "storage1"
  
  path_rule {
    name                       = "app1"
    paths                      = ["/app1/*"]
    backend_address_pool_name  = "storage1"
    backend_http_settings_name = "storage1"
    rewrite_rule_set_name      = "app1"
  }
  
  path_rule {
    name                       = "app2"
    paths                      = ["/app2/*"]
    backend_address_pool_name  = "storage2"
    backend_http_settings_name = "storage2"
    rewrite_rule_set_name      = "app2"
  }
}
~~~

App2 Rewrite Rule

~~~hcl
rewrite_rule_set {
  name = "app2"
  rewrite_rule {
    name          = "app2"
    rule_sequence = 100
    condition {
      ignore_case = true
      negate      = false
      pattern     = "/app2(/.*)"
      variable    = "var_uri_path"
    }
    url {
      components   = "path_only"
      path         = "{var_uri_path_1}"
      query_string = ""
      reroute      = false
    }
  }
}
~~~

### Detailed Rewrite Logic Explanation

Pattern Matching

~~~text
pattern = "/app1(/.*)"
variable = "var_uri_path"
~~~

Pattern: Uses regex to match the incoming path
/app1(/.*): Captures everything after "/app1" into group 1. The Brackets, which are part of the regex Capture Group syntax allows us to capture the rest of the path after "/app1".
Variable: var_uri_path refers to the full URI path of the incoming request

Path Transformation

~~~text
url {
  components   = "path_only"
  path         = "{var_uri_path_1}"
  query_string = ""
  reroute      = false
}
~~~

components = "path_only": Only rewrites the path, not the query string or other components
path = "{var_uri_path_1}": Uses the first captured group from the regex. In case we would have been using multiple capture groups, we could have used {var_uri_path_2}, {var_uri_path_3}, etc.
{var_uri_path_1}: References the first capture group (/.*)

### Request Flow Examples

#### Example 1: App1 Request

Incoming Request: GET http://cptdagwpr.swedencentral.cloudapp.azure.com/app1/container1/file.txt

Processing Flow:

- Listener: Receives request on port 80
- Path Matching: /app1/container1/file.txt matches path rule app1 (/app1/*)
- Rewrite Rule:
 - Pattern /app1(/.*) matches /app1/container1/file.txt
  - Capture group 1: /container1/file.txt
  - New path: {var_uri_path_1} = /container1/file.txt
- Backend Forward: Request sent to storage1 as GET https://cptdagwstorage1.blob.core.windows.net/container1/file.txt

#### Example 2: App2 Request

Incoming Request: GET http://cptdagwpr.swedencentral.cloudapp.azure.com/app2/container1/batman.txt

Processing Flow:

- Listener: Receives request on port 80
- Path Matching: /app2/container1/batman.txt matches path rule app2 (/app2/*)
- Rewrite Rule:
 - Pattern /app2(/.*) matches /app2/container1/batman.txt
  - Capture group 1: /container1/batman.txt
  - New path: {var_uri_path_1} = /container1/batman.txt
- Backend Forward: Request sent to storage2 as GET https://cptdagwstorage2.blob.core.windows.net/container1/batman.txt

### Health Probes

~~~hcl
probe {
  name                                      = "storage1"
  path                                      = "/container1/heartbeat.html"
  pick_host_name_from_backend_http_settings = true
  port                                      = 443
  protocol                                  = "Https"
  # ... other settings
}
~~~

Purpose: Monitors backend health by checking /container1/heartbeat.html on each storage account.

> IMPORTANT: The path does not contain app1 or app2, as the health probe checks the actual backend service directly without going through the Application Gateway's path rewrite rules.

## Test

~~~bash
$prefix = (Get-Content -Path .\terraform.tfvars.json | ConvertFrom-Json).prefix
nslookup cptdagwpr.swedencentral.cloudapp.azure.com # result into a public ip
# directly access the storage accounts
curl https://cptdagwstorage1.blob.core.windows.net/container1/spiderman.txt # 200 ok
curl https://cptdagwstorage2.blob.core.windows.net/container1/batman.txt # 200 ok
# access via the application gateway
curl "http://cptdagwpr.swedencentral.cloudapp.azure.com/app1/container1/spiderman.txt" # 200 ok
curl "http://cptdagwpr.swedencentral.cloudapp.azure.com/app2/container1/batman.txt" # 200 ok
~~~

Get the corresponding logs from the Application Gateway.

~~~powershell
$lawCustomerId=az monitor log-analytics workspace show -g $prefix -n $prefix --query customerId -o tsv
$query="AGWAccessLogs | where OriginalRequestUriWithArgs contains 'batman' or OriginalRequestUriWithArgs contains 'spiderman' | project OriginalRequestUriWithArgs,RequestUri, HttpStatus"
az monitor log-analytics query -w $lawCustomerId --analytics-query $query -o table
~~~

HttpStatus    OriginalRequestUriWithArgs      RequestUri                      TableName
------------  ------------------------------  ------------------------------  -------------
200           /app1/container1/spiderman.txt  /container1/spiderman.txt       PrimaryResult
200           /app2/container1/batman.txt     /container1/batman.txt          PrimaryResult

Get the corresponding logs from the Storage Accounts.

~~~powershell
$queryStorage="StorageBlobLogs | where TimeGenerated > ago(10m) | where ObjectKey contains 'batman' or ObjectKey contains 'spiderman'| where StatusCode == '200'| project AccountName, Uri, StatusCode, CallerIpAddress"
az monitor log-analytics query -w $lawCustomerId --analytics-query $queryStorage -o table
~~~

AccountName      CallerIpAddress    StatusCode    TableName      Uri
---------------  -----------------  ------------  -------------  --------------------------------------------------------------------------
cptdagwstorage1  10.0.0.6:29182     200           PrimaryResult  https://cptdagwstorage1.blob.core.windows.net:443/container1/spiderman.txt
cptdagwstorage2  10.0.0.6:47082     200           PrimaryResult  https://cptdagwstorage2.blob.core.windows.net:443/container1/batman.txt

## cleanup

~~~powershell
tf destroy --auto-approve
~~~

## Misc

### How to find the diagnostic settings log categories for a resource

Find all diagnostic settings log categories for a resource: https://learn.microsoft.com/en-us/azure/azure-monitor/reference/logs-index