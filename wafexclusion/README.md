# Azure Application Gateway WAF - URL-Specific Exclusion Demo

## Overview

Demonstrates how to implement **URL-specific WAF exclusions** using two separate Application Gateways with different WAF policies. This is the **correct production pattern** for excluding specific URLs from WAF protection while maintaining security on all other paths.

## Key Features

- **Dual Application Gateway Architecture**: Two separate AGWs with different WAF policies
- **URL-Specific Exclusions**: Custom allow rule for `/admin/users` path only
- **Production Pattern**: Demonstrates correct approach to WAF exclusions
- **Resource-Specific Logging**: Uses `AGWFirewallLogs` table in Log Analytics
- **JSON Backend**: nginx serves JSON responses for clear testing

## Quick Start

```bash
# Deploy infrastructure
terraform init
terraform apply -auto-approve

# Get the IP addresses
terraform output
```

## Quick Test (HTTPie)

```bash
# Get IPs from terraform output
export AGW_STD="<AGW_STANDARD_IP>"
export AGW_EXCL="<AGW_EXCLUSION_IP>"

# Test 1: Normal request (both allow)
http GET http://$AGW_STD/admin/users
http GET http://$AGW_EXCL/admin/users

# Test 2: XSS attack (Standard blocks, Exclusion allows)
http GET http://$AGW_STD/admin/users "Referer:javascript:alert(1)"   # 403 Blocked
http GET http://$AGW_EXCL/admin/users "Referer:javascript:alert(1)"  # 200 Allowed

# Test 3: XSS on different path (both block - proves path-specific)
http GET http://$AGW_STD/test-xss "Referer:javascript:alert(1)"      # 403 Blocked
http GET http://$AGW_EXCL/test-xss "Referer:javascript:alert(1)"     # 403 Blocked
```

---

## Detailed Test Cases

### Test 1: Normal Request to /admin/users

**Objective:** Verify both AGWs allow legitimate traffic without malicious payloads.

**HTTP Request:**
```bash
# Using HTTPie (recommended)
http GET http://<AGW_STD_IP>/admin/users
http GET http://<AGW_EXCL_IP>/admin/users

# Using curl
curl -v http://<AGW_STD_IP>/admin/users
curl -v http://<AGW_EXCL_IP>/admin/users
```

**Expected Result:**
- AGW-Standard: ✅ 200 OK
- AGW-Exclusion: ✅ 200 OK

Both return JSON:
```json
{
    "status": "success",
    "message": "User management endpoint",
    "timestamp": "2025-11-05T05:14:34+00:00"
}
```

**Relevant Terraform (waf-simple.tf):**
```hcl
# Backend Pool (Shared by both AGWs)
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

**Log Analytics Query:**
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/admin/users"
| where Message !contains "javascript"  // Normal requests
| project TimeGenerated, Resource, requestUri_s, action_s, Message, clientIp_s
| order by TimeGenerated desc
```

**Expected Log:** No entries (normal requests don't trigger WAF rules)

---

### Test 2: XSS Attack on /admin/users (KEY TEST)

**Objective:** Demonstrate URL-specific exclusion - same malicious payload produces different results.

**HTTP Request:**
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/admin/users "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/admin/users "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/admin/users -H "Referer: javascript:alert(1)"
curl -v http://<AGW_EXCL_IP>/admin/users -H "Referer: javascript:alert(1)"
```

**Expected Result:**
- AGW-Standard: ❌ 403 Forbidden (WAF blocked by rule 941170)
- AGW-Exclusion: ✅ 200 OK (Custom allow rule bypassed WAF)

AGW-Exclusion returns:
```json
{
    "status": "success",
    "message": "User management endpoint",
    "timestamp": "2025-11-05T05:15:17+00:00"
}
```

**Relevant Terraform (waf-simple.tf):**

AGW-Standard WAF Policy (No Custom Rules):
```hcl
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
}
```

AGW-Exclusion WAF Policy (With Custom Allow Rule):
```hcl
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
}
```

**Log Analytics Query:**
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

**Expected Logs:**

For AGW-Standard:
```
action_s: Blocked
Message: Matched Data: javascript:alert(1) found within HEADERS:Referer
ruleId_s: 941170
ruleSetType_s: OWASP
```

For AGW-Exclusion:
```
action_s: Matched
Message: Custom rule 'AllowAdminUsersPath' matched
ruleId_s: (empty - custom rule)
```

---

### Test 3: XSS Attack on /test-xss

**Objective:** Verify custom allow rule is path-specific - exclusion only applies to /admin/users.

**HTTP Request:**
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/test-xss "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/test-xss "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/test-xss -H "Referer: javascript:alert(1)"
curl -v http://<AGW_EXCL_IP>/test-xss -H "Referer: javascript:alert(1)"
```

**Expected Result:**
- AGW-Standard: ❌ 403 Forbidden (WAF blocked by rule 941170)
- AGW-Exclusion: ❌ 403 Forbidden (Custom rule doesn't match /test-xss)

**Relevant Terraform (waf-simple.tf):**
```hcl
# Custom rule in AGW-Exclusion policy
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

**Log Analytics Query:**
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/test-xss"
| where action_s == "Blocked"
| project TimeGenerated, Resource, requestUri_s, action_s, Message, ruleId_s
| order by TimeGenerated desc
```

**Expected Logs (Both AGWs):**
```
action_s: Blocked
Message: Matched Data: javascript:alert(1) found within HEADERS:Referer
ruleId_s: 941170
requestUri_s: /test-xss
```

---

### Test 4: Normal Request to Root Path

**Objective:** Verify backend is healthy and both AGWs route normal traffic correctly.

**HTTP Request:**
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/
http GET http://<AGW_EXCL_IP>/

# Using curl
curl -v http://<AGW_STD_IP>/
curl -v http://<AGW_EXCL_IP>/
```

**Expected Result:**
- AGW-Standard: ✅ 200 OK
- AGW-Exclusion: ✅ 200 OK

Both return:
```json
{
    "status": "online",
    "server": "nginx",
    "message": "Hello World! WAF Test Backend",
    "timestamp": "2025-11-05T05:18:21+00:00"
}
```

**Relevant Terraform (backend.tf):**
```hcl
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

---

### Test 5: Direct Backend Access

**Objective:** Verify NSG correctly blocks direct internet access to backend VM.

**HTTP Request:**
```bash
# Get backend public IP
terraform output backend_public_ip

# Attempt direct connection (will timeout)
http GET http://<BACKEND_PUBLIC_IP>/
curl -v http://<BACKEND_PUBLIC_IP>/admin/users --max-time 10
```

**Expected Result:**
- Result: ❌ Connection timeout

**Relevant Terraform (main.tf):**
```hcl
# NSG Rule - HTTP Only from VNet
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
    source_address_prefix      = "10.0.0.0/16"  # Only from VNet (AGW subnets)
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
- ✅ Correct security posture - all traffic must flow through WAF-protected AGW

---

### Test 6: XSS Attack on /xyz Path

**Objective:** Further validate custom allow rule scope.

**HTTP Request:**
```bash
# Using HTTPie
http GET http://<AGW_STD_IP>/xyz "Referer:javascript:alert(1)"
http GET http://<AGW_EXCL_IP>/xyz "Referer:javascript:alert(1)"

# Using curl
curl -v http://<AGW_STD_IP>/xyz -H "Referer: javascript:alert(1)"
curl -v http://<AGW_EXCL_IP>/xyz -H "Referer: javascript:alert(1)"
```

**Expected Result:**
- AGW-Standard: ❌ 403 Forbidden
- AGW-Exclusion: ❌ 403 Forbidden

**Log Analytics Query:**
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(1h)
| where requestUri_s contains "/xyz"
| where action_s == "Blocked"
| project TimeGenerated, Resource, action_s, ruleId_s, Message
| order by TimeGenerated desc
```

---

## Test Results Summary

| Test | Path | Payload | AGW-Standard | AGW-Exclusion | Proves |
|------|------|---------|--------------|---------------|--------|
| 1 | /admin/users | Normal | ✅ 200 | ✅ 200 | Both allow legitimate traffic |
| 2 | /admin/users | XSS | ❌ 403 | ✅ 200 | **URL-specific exclusion works** |
| 3 | /test-xss | XSS | ❌ 403 | ❌ 403 | **Exclusion is path-specific** |
| 4 | / | Normal | ✅ 200 | ✅ 200 | Backend healthy |
| 5 | Direct backend | Any | ❌ Timeout | ❌ Timeout | NSG properly isolates backend |
| 6 | /xyz | XSS | ❌ 403 | ❌ 403 | Further validates path-specificity |

---

## Comprehensive Log Analytics Queries

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

**See [README-simple.md](./README-simple.md) for complete query documentation.**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Shared Backend VM                         │
│  Ubuntu + nginx serving JSON on 4 endpoints                 │
│  - /                  → Hello World                          │
│  - /admin/users       → User Management (triggers 941170)    │
│  - /test-xss          → Test endpoint                        │
│  - /xyz               → Additional test path                 │
└─────────────────────────────────────────────────────────────┘
                          ▲              ▲
                          │              │
           ┌──────────────┴──┐    ┌─────┴──────────────┐
           │                 │    │                     │
    ┌──────┴──────┐   ┌──────┴────┴───┐   ┌───────────┴─────┐
    │   AGW-STD   │   │  Shared Log    │   │   AGW-EXCL      │
    │  (Standard) │   │   Analytics    │   │  (Exclusion)    │
    └─────────────┘   │   Workspace    │   └─────────────────┘
                      └────────────────┘
    WAF Policy:            Logs both         WAF Policy:
    - OWASP 3.2           AGWs to same       - OWASP 3.2
    - No custom rules     workspace          - Custom Allow Rule
                                               for /admin/users
```

---

## WAF Rule 941170

**Rule Name:** NoScript XSS InjectionChecker: Attribute Injection  
**Detects:** `javascript:` protocol in headers (Referer, User-Agent, etc.)  
**Part of:** OWASP 3.2 Core Rule Set

---

## Custom Allow Rule Mechanism

```hcl
# From waf-simple.tf - AGW-Exclusion policy
custom_rules {
  name      = "AllowAdminUsersPath"
  priority  = 1                    # Evaluated BEFORE managed rules
  rule_type = "MatchRule"
  action    = "Allow"              # Bypasses ALL managed rules
  
  match_conditions {
    match_variables {
      variable_name = "RequestUri"
    }
    operator     = "BeginsWith"
    match_values = ["/admin/users"]  # Only this path
  }
}
```

**How It Works:**
1. Request arrives at AGW-Exclusion
2. Custom rules evaluated first (priority 1)
3. If RequestUri matches `/admin/users` → Action: Allow
4. Request bypasses ALL managed rules (including 941170)
5. Request forwarded to backend

**Why /test-xss Still Gets Blocked:**
1. Custom rule checked: `/test-xss` doesn't match `/admin/users`
2. Proceeds to managed rules evaluation
3. Rule 941170 detects `javascript:` in Referer
4. Request blocked with 403

---

## Production Recommendations

### ⚠️ Don't Use Custom Allow Rules in Production

This demo uses a **broad custom allow rule** that bypasses ALL WAF protection for `/admin/users`. 

### ✅ Better Approach: Managed Rule Exclusions

```hcl
managed_rules {
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
  
  managed_rule_set {
    type    = "OWASP"
    version = "3.2"
  }
}
```

**Benefits:**
- Only excludes Referer header from rule 941170
- Other headers still checked by 941170
- All other XSS rules still inspect Referer
- More granular and secure

## Files

- `waf-simple.tf` - Main infrastructure (2 AGWs, 2 WAF policies)
- `main.tf` - Shared resources (VNet, NSG, Log Analytics)
- `backend.tf` - Shared backend VM with nginx
- `scripts/setup-webserver-simple.sh` - nginx configuration
- `outputs.tf` - Deployment outputs
- `waf.tf.old` - Legacy configuration (archived)

## Cleanup

```bash
terraform destroy -auto-approve
```

## References

- [Azure WAF Rule Groups (OWASP 3.2)](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-crs-rulegroups-rules)
- [WAF Custom Rules Overview](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview)
- [WAF Exclusion Configuration](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-waf-configuration)
- [Resource-Specific Diagnostic Settings](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs)
