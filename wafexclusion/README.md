# Azure Application Gateway WAF - URL-Specific Exclusion Demo

## Overview

Demonstrates how to exclude certain URLs from CRS "941170" on Azure Application Gateway WAF.

## WAF Policy Comparison

This setup deploys two Application Gateways with different WAF policies to demonstrate path-specific exclusions.

Standard Policy: Uses only managed OWASP rules. All traffic is inspected against rule 941170 (XSS detection). XSS patterns are blocked on all paths.

Exclusion Policy: Adds a custom allow rule with priority 1. The custom rule matches requests to /admin/users and allows them before managed rules execute. XSS patterns in /admin/users bypass rule 941170. Other paths still trigger rule 941170 blocks.

The exclusion works because custom rules are evaluated before managed rules. When a request to /admin/users arrives, the Allow action stops further inspection. Requests to other paths skip the custom rule and continue to managed rule evaluation.

## Key Features

- **Dual Application Gateway Architecture**: Two separate AGWs with different WAF policies
- **URL-Specific Exclusions**: Custom allow rule for `/admin/users` path only
- **Production Pattern**: Demonstrates correct approach to WAF exclusions
- **Resource-Specific Logging**: Uses `AGWFirewallLogs` table in Log Analytics
- **JSON Backend**: nginx serves JSON responses for clear testing

## Quick Start

```powershell
# Deploy infrastructure
terraform init
terraform apply -auto-approve

# Get the IP addresses
terraform output

# Get IPs from terraform output
$agwStandardPubIP = terraform output -raw agw_standard_public_ip
$agwExclusionPubIP = terraform output -raw agw_exclusion_public_ip
$lawName = terraform output -raw log_analytics_workspace_name
$rgName = terraform output -raw resource_group_name
$workspaceId = az monitor log-analytics workspace show --resource-group $rgName --workspace-name $lawName --query "customerId" --out tsv
```

## Test: Normal request Standard AGW

~~~powershell
http GET http://$agwStandardPubIP/admin/users
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 20:35:04 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T20:35:04+00:00"
}
~~~

~~~powershell

# Get Application Gateway access logs (last 1 hour)
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where RuleId == '941170' | where InstanceId == 'appgw_0'| where RequestUri == '/admin/users'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

Output: Empty (no WAF blocks for normal requests)

| field | value |
| :--- | :--- |
| Action | Allowed |
| DetailedData | |
| DetailedMessage | |
| Message | Access allowed. Pattern match /admin/users, at RequestUri. |
| RequestUri | /admin/users |
| RuleId | AllowAdminUsersPath |
| RuleSetType | Custom |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T20:52:23Z |

## Test: Normal request Exclusion AGW

~~~powershell
http GET http://$agwExclusionPubIP/admin/users
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 20:52:23 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T20:52:23+00:00"
}
~~~

~~~powershell
# First, get the workspace customer ID (required for queries)
$workspaceId = az monitor log-analytics workspace show --resource-group $rgName --workspace-name $lawName --query "customerId" --out tsv

# Get Application Gateway access logs (last 1 hour)
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where RuleId == '941170' |where InstanceId == 'appgw_1'| where RequestUri == '/admin/users'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

Output:

| field | value |
| :--- | :--- |
| Action | Matched |
| DetailedData | { found within [REQUEST_HEADERS:]} |
| DetailedMessage | |
| Message | 'Other bots' |
| RequestUri | /admin/users |
| RuleId | 300700 |
| RuleSetType | Microsoft_BotManagerRuleSet |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T20:35:03Z |

| field | value |
| :--- | :--- |
| Action | Matched |
| DetailedData | {74.235.228.45 found within [REQUEST_HEADERS:Host:74.235.228.45]} |
| DetailedMessage | Pattern match ^[\d.:]+$ at REQUEST_HEADERS:host. |
| Message | Host header is a numeric IP address |
| RequestUri | /admin/users |
| RuleId | 920350 |
| RuleSetType | OWASP CRS |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T20:35:03Z |


## Test: XSS attack - Standard block

~~~powershell
http GET "http://$agwStandardPubIP/admin/users?next=javascript:alert(1)" # 403 Blocked
onnection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 20:53:27 GMT
Server: Microsoft-Azure-Application-Gateway/v2

<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
~~~

~~~powershell
# Get Application Gateway access logs (last 1 hour)
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where InstanceId == 'appgw_0'| where RequestUri == '/admin/users?next=javascript:alert(1)'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

Output (could not find a block for where RuleId == '941170', so i did include all logs for that RequestUri): 

| field | value |
| :--- | :--- |
| Action | Allowed |
| DetailedData | |
| DetailedMessage | |
| Message | Access allowed. Pattern match /admin/users, at RequestUri. |
| RequestUri | /admin/users?next=javascript:alert(1) |
| RuleId | AllowAdminUsersPath |
| RuleSetType | Custom |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T20:54:54Z |

## Test: XSS attack - Exclusion allows

~~~powershell
http GET "http://$agwExclusionPubIP/admin/users?next=javascript:alert(1)" # 200 Allowed
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 20:54:54 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T20:54:54+00:00"
}
~~~

~~~powershell
# Get Application Gateway access logs (last 1 hour)
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where RuleId == '941170' | where InstanceId == 'appgw_1'| where RequestUri == '/admin/users?next=javascript:alert(1)'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

| field | value |
| :--- | :--- |
| Action | Blocked |
| DetailedData | Matched Data: javascript:alert( found within ARGS:next: javascript:alert(1) |
| DetailedMessage | Pattern match (?i)(?:\W|^)(?:javascript:(?:[\s\S]+[=\(\[\.<]|[\s\S]*?(?:\bname\b|\[ux]\d))|data:(?:(?:[a-z]\w+\/\w[\w+-]+\w)?[;,]|[\s\S]*?;[\s\S]*?\b(?:base64|charset=)|[\s\S]*?,[\s\S]*?<[\s\S]*?\w[\s\S]*?>))|@\W*?i\W*?m\W*?p\W*?o\W*?r\W*?t\W*?(?:\/\*[\s\S]*?)?(?:["']|\W*?u\W*?r\W*?l[\s\S]*?\()|\W*?-\W*?m\W*?o\W*?z\W*?-\W*?b\W*?i\W*?n\W*?d\W*?i\W*?n\W*?g[\s\S]*?:[\s\S]*?\W*?u\W*?r\W*?l[\s\S]*?\( at ARGS. |
| Message | NoScript XSS InjectionChecker: Attribute Injection |
| RequestUri | /admin/users?next=javascript:alert(1) |
| RuleId | **941170** |
| RuleSetType | OWASP CRS |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T20:53:27Z |

## Test: XSS on different path - Standard block

~~~powershell
http GET "http://$agwStandardPubIP/test-xss?next=javascript:alert(1)"         # 403 Blocked
HTTP/1.1 403 Forbidden
Connection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 21:12:05 GMT
Server: Microsoft-Azure-Application-Gateway/v2

<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
~~~

~~~powershell
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where RuleId == '941170' | where InstanceId == 'appgw_0'| where RequestUri == '/test-xss?next=javascript:alert(1)'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

| field | value |
| :--- | :--- |
| Action | Blocked |
| DetailedData | Matched Data: javascript:alert( found within ARGS:next: javascript:alert(1) |
| DetailedMessage | Pattern match (?i)(?:\W|^)(?:javascript:(?:[\s\S]+[=\(\[\.<]|[\s\S]*?(?:\bname\b|\[ux]\d))|data:(?:(?:[a-z]\w+\/\w[\w+-]+\w)?[;,]|[\s\S]*?;[\s\S]*?\b(?:base64|charset=)|[\s\S]*?,[\s\S]*?<[\s\S]*?\w[\s\S]*?>))|@\W*?i\W*?m\W*?p\W*?o\W*?r\W*?t\W*?(?:\/\*[\s\S]*?)?(?:["']|\W*?u\W*?r\W*?l[\s\S]*?\()|\W*?-\W*?m\W*?o\W*?z\W*?-\W*?b\W*?i\W*?n\W*?d\W*?i\W*?n\W*?g[\s\S]*?:[\s\S]*?\W*?u\W*?r\W*?l[\s\S]*?\( at ARGS. |
| Message | NoScript XSS InjectionChecker: Attribute Injection |
| RequestUri | /test-xss?next=javascript:alert(1) |
| RuleId | **941170** |
| RuleSetType | OWASP CRS |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T21:12:05Z |


## Test: XSS on different path - Exclusion block

~~~powershell
http GET "http://$agwExclusionPubIP/test-xss?next=javascript:alert(1)"        # 403 Blocked
Connection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 21:12:09 GMT
Server: Microsoft-Azure-Application-Gateway/v2

<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
~~~

~~~powershell
# Get Application Gateway access logs (last 1 hour)
az monitor log-analytics query -w $workspaceId --analytics-query "AGWFirewallLogs| where TimeGenerated > ago(1h) | where RuleId == '941170' | where InstanceId == 'appgw_1'| where RequestUri == '/test-xss?next=javascript:alert(1)'| project TimeGenerated, RequestUri, RuleSetType, RuleId, Message, Action, DetailedMessage, DetailedData | order by TimeGenerated desc " --out table
~~~

| field | value |
| :--- | :--- |
| Action | Blocked |
| DetailedData | Matched Data: javascript:alert( found within ARGS:next: javascript:alert(1) |
| DetailedMessage | Pattern match (?i)(?:\W|^)(?:javascript:(?:[\s\S]+[=\(\[\.<]|[\s\S]*?(?:\bname\b|\[ux]\d))|data:(?:(?:[a-z]\w+\/\w[\w+-]+\w)?[;,]|[\s\S]*?;[\s\S]*?\b(?:base64|charset=)|[\s\S]*?,[\s\S]*?<[\s\S]*?\w[\s\S]*?>))|@\W*?i\W*?m\W*?p\W*?o\W*?r\W*?t\W*?(?:\/\*[\s\S]*?)?(?:["']|\W*?u\W*?r\W*?l[\s\S]*?\()|\W*?-\W*?m\W*?o\W*?z\W*?-\W*?b\W*?i\W*?n\W*?d\W*?i\W*?n\W*?g[\s\S]*?:[\s\S]*?\W*?u\W*?r\W*?l[\s\S]*?\( at ARGS. |
| Message | NoScript XSS InjectionChecker: Attribute Injection |
| RequestUri | /test-xss?next=javascript:alert(1) |
| RuleId | **941170** |
| RuleSetType | OWASP CRS |
| TableName | PrimaryResult |
| TimeGenerated | 2025-11-05T21:12:09Z |

## Terraform Implementation and Security Risks

### How the Exclusion Works in Terraform

The exclusion is implemented using a custom rule in the WAF policy. In waf.tf, the policy with_exclusion contains a custom_rules block:

```terraform
custom_rules {
  name      = "AllowAdminUsersPath"
  priority  = 1
  rule_type = "MatchRule"
  action    = "Allow"

  match_conditions {
    match_variables {
      variable_name = "RequestUri"
    }
    operator     = "BeginsWith"
    match_values = ["/admin/users"]
  }
}
```

The custom rule uses priority 1 and action Allow. When a request matches the RequestUri pattern, WAF immediately allows it and stops processing. No managed OWASP rules are evaluated for matching requests.

### Critical Security Risks

Complete WAF Bypass: Once the custom Allow rule matches, all managed rules are skipped. The request bypasses not just rule 941170, but the entire OWASP ruleset including SQL injection (942xxx), command injection (932xxx), remote file inclusion (931xxx), and all other protections.

Multi-Vector Attacks: A single request to /admin/users can contain multiple attack patterns. Example: /admin/users?next=javascript:alert(1)&id=1' OR '1'='1 contains both XSS and SQL injection. Both attacks reach the backend unfiltered.

Path Scope Too Broad: The BeginsWith operator matches /admin/users, /admin/users/123, /admin/users/delete, and all subpaths. Every endpoint under this path loses WAF protection entirely.

No Validation Layer: The backend receives malicious payloads directly. If the application has any vulnerability (improper input sanitization, database query construction, template rendering), attackers can exploit it through the allowed path.

### Recommendation

Use WAF exclusions sparingly and only when absolutely necessary.

