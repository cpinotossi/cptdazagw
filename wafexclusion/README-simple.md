# Azure Application Gateway WAF - URL-Specific Exclusion Demo

This demo shows how to implement **URL-specific WAF exclusions** using two separate Application Gateways with different WAF policies.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Shared Backend                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Ubuntu VM with nginx serving JSON responses          │   │
│  │ - /                  → Hello World                    │   │
│  │ - /admin/users       → User Management (triggers WAF) │   │
│  │ - /test-xss          → Test endpoint                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          ▲              ▲
                          │              │
           ┌──────────────┴──┐    ┌─────┴──────────────┐
           │                 │    │                     │
    ┌──────┴──────┐   ┌──────┴────┴───┐   ┌───────────┴─────┐
    │   AGW-STD   │   │   WAF Policy   │   │   AGW-EXCL      │
    │  (Standard) │   │   (Standard)   │   │  (Exclusion)    │
    └─────────────┘   └────────────────┘   └─────────────────┘
    Blocks all XSS     Blocks all 941170       Has custom rule:
    attempts           patterns                 "Allow /admin/users"
```

## What This Demo Shows

### Two Application Gateways Testing the Same URLs:

1. **AGW-STD (Standard Protection)**
   - WAF Policy: Standard managed rules only
   - Behavior: Blocks ALL requests matching rule 941170
   - Test Result: `/admin/users` with `javascript:` Referer → **403 Forbidden**

2. **AGW-EXCL (With Exclusion)**
   - WAF Policy: Standard managed rules + Custom allow rule
   - Custom Rule: `IF RequestUri MATCHES '/admin/users' THEN ALLOW`
   - Test Result: `/admin/users` with `javascript:` Referer → **200 OK**

### Key Concept: Custom Allow Rules vs Managed Rule Exclusions

**This demo uses Custom Allow Rules** (not managed rule exclusions):
- Custom rules are evaluated **BEFORE** managed rules
- When a request matches a custom allow rule, WAF processing **stops**
- The request bypasses all managed rules (including 941170)

**Alternative: Managed Rule Exclusions** (not used here):
- Exclude specific request components from specific rules
- Example: "Exclude Referer header from rule 941170 evaluation"
- More granular but requires rule group/rule ID knowledge

## WAF Rule 941170

**Rule ID:** 941170  
**Rule Name:** NoScript XSS InjectionChecker: Attribute Injection  
**What it blocks:** Detects `javascript:` protocol in various locations (Referer, headers, URL params)  
**Example payload:** `Referer: javascript:alert(1)`

## Infrastructure

### Shared Resources
- **1 Backend VM:** Ubuntu with nginx serving JSON
- **1 Log Analytics Workspace:** Centralized logging for both AGWs
- **Resource-Specific Logs:** Uses `AGWFirewallLogs` table

### Per-AGW Resources
- **2 Public IP Addresses:** One for each AGW
- **2 Application Gateways:** One standard, one with exclusions
- **2 WAF Policies:** Different rule configurations

## Prerequisites

- Azure subscription
- Azure CLI or Terraform
- `curl` for testing

## Deployment

```bash
terraform init
terraform plan
terraform apply
```

## Testing

After deployment, get the public IP addresses:

```bash
terraform output
```

You'll see:
- `agw_standard_public_ip` - Standard AGW (blocks all XSS)
- `agw_exclusion_public_ip` - Exclusion AGW (allows /admin/users)

---

## Test Cases

### Test 1: Normal Request to /admin/users

**Objective:** Verify both AGWs allow legitimate traffic without malicious payloads.

#### HTTP Request
```bash
# Using HTTPie (recommended)
http GET http://<AGW_STD_IP>/admin/users
http GET http://<AGW_EXCL_IP>/admin/users

# Using curl
curl -v http://<AGW_STD_IP>/admin/users
curl -v http://<AGW_EXCL_IP>/admin/users
```

#### Expected Result
- **AGW-Standard:** ✅ 200 OK
- **AGW-Exclusion:** ✅ 200 OK

Both should return:
```json
{
    "status": "success",
    "message": "User management endpoint",
    "timestamp": "2025-11-05T05:14:34+00:00"
}
```

#### Relevant Terraform Configuration

**Backend Pool (Shared):**
```hcl
# From waf-simple.tf
backend_address_pool {
  name  = "backend-pool"
  fqdns = []
  ip_addresses = [
    azurerm_network_interface.backend.private_ip_address
  ]
}

backend_http_settings {
  name                  = "backend-http-settings"
  cookie_based_affinity = "Disabled"
  port                  = 80
  protocol              = "Http"
  request_timeout       = 60
}
```

#### Log Analytics Query
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/admin/users"
| where Message !contains "javascript"  // Normal requests
| project TimeGenerated, Resource, requestUri_s, action_s, Message, clientIp_s
| order by TimeGenerated desc
```

**Expected Log Result:** No entries (normal requests aren't logged as they don't trigger WAF rules)

---

### Test 2: XSS Attack on /admin/users (🎯 KEY TEST)

**Objective:** Demonstrate URL-specific exclusion - same malicious payload produces different results.

#### HTTP Request
```bash
# Using HTTPie (recommended)
http GET http://<AGW_STD_IP>/admin/users "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/admin/users "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/admin/users \
  -H "Referer: javascript:alert(1)"
  
curl -v http://<AGW_EXCL_IP>/admin/users \
  -H "Referer: javascript:alert(1)"
```

#### Expected Result
- **AGW-Standard:** ❌ 403 Forbidden (WAF blocked by rule 941170)
- **AGW-Exclusion:** ✅ 200 OK (Custom allow rule bypassed WAF)

AGW-Exclusion returns JSON:
```json
{
    "status": "success",
    "message": "User management endpoint",
    "timestamp": "2025-11-05T05:15:17+00:00"
}
```

#### Relevant Terraform Configuration

**AGW-Standard WAF Policy (No Custom Rules):**
```hcl
# From waf-simple.tf
resource "azurerm_web_application_firewall_policy" "standard" {
  name                = "${local.resource_prefix}-waf-standard-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = azurerm_resource_group.main.tags
}
```

**AGW-Exclusion WAF Policy (With Custom Allow Rule):**
```hcl
# From waf-simple.tf
resource "azurerm_web_application_firewall_policy" "with_exclusion" {
  name                = "${local.resource_prefix}-waf-exclusion-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  # Custom rule evaluated BEFORE managed rules
  custom_rules {
    name      = "AllowAdminUsersPath"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Allow"  # Bypasses ALL managed rules

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator     = "BeginsWith"
      match_values = ["/admin/users"]
    }
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = azurerm_resource_group.main.tags
}
```

#### Log Analytics Query
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/admin/users"
| where Message contains "javascript" or action_s == "Blocked"
| project TimeGenerated, 
          Resource, 
          requestUri_s, 
          action_s, 
          Message, 
          ruleId_s,
          ruleSetType_s,
          clientIp_s
| order by TimeGenerated desc
```

**Expected Log Results:**

For **AGW-Standard:**
```
action_s: Blocked
Message: Matched Data: javascript:alert(1) found within HEADERS:Referer: javascript:alert(1)
ruleId_s: 941170
ruleSetType_s: OWASP
```

For **AGW-Exclusion:**
```
action_s: Matched
Message: Custom rule 'AllowAdminUsersPath' matched
ruleId_s: (empty - custom rule)
```

---

### Test 3: XSS Attack on /test-xss

**Objective:** Verify custom allow rule is path-specific - exclusion only applies to /admin/users.

#### HTTP Request
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/test-xss "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/test-xss "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/test-xss \
  -H "Referer: javascript:alert(1)"
  
curl -v http://<AGW_EXCL_IP>/test-xss \
  -H "Referer: javascript:alert(1)"
```

#### Expected Result
- **AGW-Standard:** ❌ 403 Forbidden (WAF blocked by rule 941170)
- **AGW-Exclusion:** ❌ 403 Forbidden (Custom rule doesn't match /test-xss)

Both return:
```html
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
```

#### Relevant Terraform Configuration

**Custom Rule Match Condition:**
```hcl
# From waf-simple.tf - Custom rule in AGW-Exclusion policy
match_conditions {
  match_variables {
    variable_name = "RequestUri"
  }
  operator     = "BeginsWith"
  match_values = ["/admin/users"]  # Only matches /admin/users, NOT /test-xss
}
```

**How It Works:**
1. Request to `/test-xss` arrives at AGW-Exclusion
2. Custom rule evaluated: `/test-xss` does NOT begin with `/admin/users`
3. Custom rule doesn't match → proceed to managed rules
4. Managed rule 941170 detects `javascript:` in Referer
5. Request blocked with 403

#### Log Analytics Query
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/test-xss"
| where action_s == "Blocked"
| project TimeGenerated, 
          Resource, 
          requestUri_s, 
          action_s, 
          Message, 
          ruleId_s
| order by TimeGenerated desc
```

**Expected Log Results for Both AGWs:**
```
action_s: Blocked
Message: Matched Data: javascript:alert(1) found within HEADERS:Referer
ruleId_s: 941170
requestUri_s: /test-xss
```

---

### Test 4: Normal Request to Root Path

**Objective:** Verify backend is healthy and both AGWs route normal traffic correctly.

#### HTTP Request
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/
http GET http://<AGW_EXCL_IP>/

# Using curl
curl -v http://<AGW_STD_IP>/
curl -v http://<AGW_EXCL_IP>/
```

#### Expected Result
- **AGW-Standard:** ✅ 200 OK
- **AGW-Exclusion:** ✅ 200 OK

Both return:
```json
{
    "status": "online",
    "server": "nginx",
    "message": "Hello World! WAF Test Backend",
    "timestamp": "2025-11-05T05:18:21+00:00"
}
```

#### Relevant Terraform Configuration

**Backend VM Configuration:**
```hcl
# From backend.tf
resource "azurerm_linux_virtual_machine" "backend" {
  name                = "${local.resource_prefix}-backend-vm-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  
  custom_data = base64encode(templatefile("${path.module}/scripts/setup-webserver-simple.sh", {}))
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
```

**Backend Script (setup-webserver-simple.sh):**
```bash
location / {
    default_type application/json;
    return 200 '{"status":"online","server":"nginx","message":"Hello World! WAF Test Backend","timestamp":"$time_iso8601"}';
}
```

#### Log Analytics Query
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s == "/" or requestUri_s == ""
| project TimeGenerated, Resource, action_s, Message
| order by TimeGenerated desc
```

---

### Test 5: Direct Backend Access

**Objective:** Verify NSG correctly blocks direct internet access to backend VM.

#### HTTP Request
```bash
# Get backend public IP
terraform output backend_public_ip

# Attempt direct connection (will timeout)
http GET http://<BACKEND_PUBLIC_IP>/
curl -v http://<BACKEND_PUBLIC_IP>/admin/users --max-time 10
```

#### Expected Result
- **Result:** ❌ Connection timeout (No route to host)

#### Relevant Terraform Configuration

**NSG Rule - HTTP Only from VNet:**
```hcl
# From main.tf
resource "azurerm_network_security_group" "backend" {
  name                = "${local.resource_prefix}-backend-nsg-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.0.0.0/16"  # ✅ Only from VNet (AGW subnets)
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
```

**Security Analysis:**
- ✅ Application Gateways can reach backend (they're in 10.0.1.0/24 and 10.0.3.0/24)
- ❌ Direct internet access blocked (source must be from VNet 10.0.0.0/16)
- ✅ **Correct security posture** - all traffic must flow through WAF-protected AGW

#### Log Analytics Query
```kusto
// No logs expected - traffic never reaches Application Gateway
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where DestinationIP == "<BACKEND_PRIVATE_IP>"
| where SourceIP !startswith "10.0."  // External sources
| project TimeGenerated, SourceIP, DestinationPort, FlowStatus
```

---

### Test 6: XSS Attack on /xyz Path

**Objective:** Further validate custom allow rule scope.

#### HTTP Request
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/xyz "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/xyz "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/xyz \
  -H "Referer: javascript:alert(1)"
  
curl -v http://<AGW_EXCL_IP>/xyz \
  -H "Referer: javascript:alert(1)"
```

#### Expected Result
- **AGW-Standard:** ❌ 403 Forbidden
- **AGW-Exclusion:** ❌ 403 Forbidden

#### Relevant Terraform Configuration

Same as Test 3 - custom rule only matches `/admin/users`.

#### Log Analytics Query
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/xyz"
| where action_s == "Blocked"
| project TimeGenerated, Resource, action_s, ruleId_s, Message
| order by TimeGenerated desc
```

---

## Comprehensive Log Analysis Queries

### View All WAF Activity (Last Hour)
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, 
          AGW = tostring(split(Resource, "/")[8]),
          URI = requestUri_s,
          Action = action_s,
          Rule = ruleId_s,
          Message,
          ClientIP = clientIp_s
| order by TimeGenerated desc
```

### Compare Behavior Between AGWs
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/admin/users"
| summarize Count=count(), 
            Actions=make_set(action_s), 
            Rules=make_set(ruleId_s) 
  by Resource, requestUri_s
| project Resource, 
          Count, 
          Actions = strcat_array(Actions, ", "), 
          Rules = strcat_array(Rules, ", ")
```

### Find All Blocked Requests
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(24h)
| where action_s == "Blocked"
| summarize Count=count() by requestUri_s, ruleId_s, Message
| order by Count desc
```

### Verify Custom Rule Matches
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where Message contains "AllowAdminUsersPath"
| project TimeGenerated, requestUri_s, action_s, Message, clientIp_s
| order by TimeGenerated desc
```

### Detect Rule 941170 Triggers
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where ruleId_s == "941170"
| project TimeGenerated,
          AGW = tostring(split(Resource, "/")[8]),
          URI = requestUri_s,
          Action = action_s,
          Message
| order by TimeGenerated desc
```

## Understanding the Results

### Why does AGW-EXCL allow malicious requests to `/admin/users`?

The custom allow rule in the exclusion WAF policy:
```hcl
match_conditions {
  match_variables {
    variable_name = "RequestUri"
  }
  operator       = "Contains"
  match_values   = ["/admin/users"]
}
action = "Allow"
```

This rule:
1. Matches BEFORE managed rules execute
2. Allows the request through immediately
3. Skips all managed rule evaluation (including 941170)

### Why does AGW-EXCL still block `/test-xss`?

The custom allow rule only matches `/admin/users`:
- Requests to `/test-xss` don't match the custom rule
- They proceed to managed rule evaluation
- Rule 941170 detects the `javascript:` protocol
- Request is blocked

## Log Analysis

Query WAF logs in Log Analytics:

```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where action_s == "Blocked" or action_s == "Matched"
| project TimeGenerated, host_s, requestUri_s, action_s, Message
| order by TimeGenerated desc
```

Filter by Application Gateway:

```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where Resource contains "agw-std"  // or "agw-excl"
| project TimeGenerated, requestUri_s, action_s, Message
```

## Production Considerations

### ⚠️ This Demo is for Learning

The exclusion AGW deliberately weakens security to demonstrate WAF behavior. In production:

1. **Use Managed Rule Exclusions** instead of broad custom allow rules
2. **Exclude specific components** (e.g., only Referer header from 941170)
3. **Don't bypass entire managed rulesets** for a URL path
4. **Validate business justification** for each exclusion
5. **Monitor exclusion effectiveness** continuously

### Better Production Pattern: Managed Rule Exclusions

Instead of a custom allow rule, use managed rule exclusions:

```hcl
exclusion {
  match_variable          = "RequestHeaderNames"
  selector               = "Referer"
  selector_match_operator = "Equals"
  
  excluded_rule_set {
    rule_group {
      rule_group_name = "REQUEST-941-APPLICATION-ATTACK-XSS"
      excluded_rules  = ["941170"]
    }
  }
}
```

This approach:
- Only excludes Referer header from rule 941170
- Other rules still inspect the Referer
- Other headers are still checked by 941170
- More granular and secure

## Files

- `main.tf` - Dual AGW infrastructure
- `waf-simple.tf` - WAF policies (standard and exclusion)
- `scripts/setup-webserver-simple.sh` - nginx backend configuration
- `outputs.tf` - AGW public IPs
- `variables.tf` - Configurable parameters

## Cleanup

```bash
terraform destroy
```

## References

- [Azure WAF Rule Groups](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-crs-rulegroups-rules)
- [WAF Custom Rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview)
- [WAF Exclusions](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-waf-configuration)
