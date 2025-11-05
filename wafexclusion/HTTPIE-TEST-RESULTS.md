# WAF Exclusion Demo - HTTPie Test Results

**Test Date:** November 5, 2025  
**Testing Tool:** HTTPie 3.2.3  
**AGW-Standard IP:** 20.185.184.176  
**AGW-Exclusion IP:** 20.185.189.225  

---

## Test 1: Normal Request to /admin/users

### AGW-Standard (20.185.184.176)
```bash
http GET http://20.185.184.176/admin/users
```

**Result:** ✅ **200 OK**
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 05:14:34 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T05:14:34+00:00"
}
```

### AGW-Exclusion (20.185.189.225)
```bash
http GET http://20.185.189.225/admin/users
```

**Result:** ✅ **200 OK**
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 05:14:37 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T05:14:37+00:00"
}
```

**Analysis:** Both AGWs allow normal requests without malicious headers. Earlier PowerShell tests showed AGW-Standard blocking this, but HTTPie test succeeds. This suggests the PowerShell User-Agent or other default headers may have triggered the WAF.

---

## Test 2: XSS Attack on /admin/users (🎯 KEY TEST)

**Attack Payload:** `Referer: javascript:alert(1)`  
**Target Rule:** OWASP 3.2 Rule 941170 (NoScript XSS InjectionChecker)

### AGW-Standard (20.185.184.176) - Should BLOCK
```bash
http GET http://20.185.184.176/admin/users "Referer:javascript:alert(1)"
```

**Result:** ❌ **403 Forbidden** (WAF Blocked)
```http
HTTP/1.1 403 Forbidden
Connection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 05:15:14 GMT
Server: Microsoft-Azure-Application-Gateway/v2

<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
```

### AGW-Exclusion (20.185.189.225) - Should ALLOW
```bash
http GET http://20.185.189.225/admin/users "Referer:javascript:alert(1)"
```

**Result:** ✅ **200 OK** (Custom Rule Bypassed WAF)
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 97
Content-Type: application/json
Date: Wed, 05 Nov 2025 05:15:17 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "User management endpoint",
    "status": "success",
    "timestamp": "2025-11-05T05:15:17+00:00"
}
```

**✅ SUCCESS:** Same malicious payload, same path, **different results** based on WAF policy!

---

## Test 3: XSS Attack on /test-xss (Verify Exclusion Scope)

**Attack Payload:** `Referer: javascript:alert(1)`  
**Purpose:** Verify custom allow rule only applies to `/admin/users`

### AGW-Standard (20.185.184.176) - Should BLOCK
```bash
http GET http://20.185.184.176/test-xss "Referer:javascript:alert(1)"
```

**Result:** ❌ **403 Forbidden** (WAF Blocked)
```http
HTTP/1.1 403 Forbidden
Connection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 05:18:00 GMT
Server: Microsoft-Azure-Application-Gateway/v2
```

### AGW-Exclusion (20.185.189.225) - Should ALSO BLOCK
```bash
http GET http://20.185.189.225/test-xss "Referer:javascript:alert(1)"
```

**Result:** ❌ **403 Forbidden** (Custom Rule Doesn't Match)
```http
HTTP/1.1 403 Forbidden
Connection: keep-alive
Content-Length: 179
Content-Type: text/html
Date: Wed, 05 Nov 2025 05:18:03 GMT
Server: Microsoft-Azure-Application-Gateway/v2
```

**✅ SUCCESS:** Both AGWs block the attack on `/test-xss`, proving the custom allow rule is **path-specific** to `/admin/users` only.

---

## Test 4: Normal Request to Root Path

### AGW-Standard (20.185.184.176)
```bash
http GET http://20.185.184.176/
```

**Result:** ✅ **200 OK**
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 118
Content-Type: application/json
Date: Wed, 05 Nov 2025 05:18:21 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "Hello World! WAF Test Backend",
    "server": "nginx",
    "status": "online",
    "timestamp": "2025-11-05T05:18:21+00:00"
}
```

### AGW-Exclusion (20.185.189.225)
```bash
http GET http://20.185.189.225/
```

**Result:** ✅ **200 OK**
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 118
Content-Type: application/json
Date: Wed, 05 Nov 2025 05:18:24 GMT
Server: nginx/1.18.0 (Ubuntu)

{
    "message": "Hello World! WAF Test Backend",
    "server": "nginx",
    "status": "online",
    "timestamp": "2025-11-05T05:18:24+00:00"
}
```

**Analysis:** Both AGWs allow normal requests to root path. Backend is healthy and responding.

---

## Test 5: Direct Backend Access (Bypasses WAF)

### Direct to Backend VM (20.121.186.62)
```bash
http GET http://20.121.186.62/
http GET http://20.121.186.62/admin/users
```

**Result:** ❌ **Timeout**
```
http: error: Request timed out (0s).
```

**Analysis:** NSG rules block direct internet access to backend VM. This is correct security posture - all traffic must flow through Application Gateway.

---

## Test 6: XSS Attack on /xyz Path

**Attack Payload:** `Referer: javascript:alert(1)`  
**Purpose:** Further verify exclusion scope

### AGW-Standard (20.185.184.176)
```bash
http GET http://20.185.184.176/xyz "Referer:javascript:alert(1)"
```

**Result:** ❌ **403 Forbidden** (WAF Blocked)

### AGW-Exclusion (20.185.189.225)
```bash
http GET http://20.185.189.225/xyz "Referer:javascript:alert(1)"
```

**Result:** ❌ **403 Forbidden** (Custom Rule Doesn't Match)

**✅ SUCCESS:** Confirms the custom allow rule is limited to `/admin/users` path only.

---

## Summary

### 🎯 Demonstration Objectives: ACHIEVED

| Test | Purpose | AGW-Standard | AGW-Exclusion | Result |
|------|---------|--------------|---------------|--------|
| **Test 2** | XSS on /admin/users | 403 Blocked | 200 Allowed | ✅ **CORE DEMO WORKING** |
| **Test 3** | XSS on /test-xss | 403 Blocked | 403 Blocked | ✅ **PATH-SPECIFIC** |
| **Test 6** | XSS on /xyz | 403 Blocked | 403 Blocked | ✅ **PATH-SPECIFIC** |

### Key Findings

1. **Custom Allow Rule Works Perfectly**
   - URL-specific exclusion successfully demonstrated
   - Same malicious payload produces different results based on path
   - Only `/admin/users` bypasses WAF on AGW-Exclusion

2. **WAF Rule 941170 Detection**
   - Detects `javascript:` protocol in Referer header
   - Blocks consistently across all paths except excluded ones
   - Works identically on both AGWs when path doesn't match exclusion

3. **Security Posture**
   - Backend VM properly isolated (direct access blocked)
   - Normal requests allowed on both AGWs
   - Malicious requests blocked except where explicitly excluded

### HTTPie Commands for Quick Testing

```bash
# Normal request
http GET http://20.185.189.225/admin/users

# XSS attack (will be allowed on AGW-Exclusion)
http GET http://20.185.189.225/admin/users "Referer:javascript:alert(1)"

# XSS attack on different path (will be blocked)
http GET http://20.185.189.225/test-xss "Referer:javascript:alert(1)"

# Test AGW-Standard (should block)
http GET http://20.185.184.176/admin/users "Referer:javascript:alert(1)"
```

### Production Recommendations

⚠️ **Do Not Use Custom Allow Rules in Production**

This demo uses a broad custom allow rule that bypasses ALL WAF protection. In production, use managed rule exclusions instead:

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
- Only excludes specific header from specific rule
- Other headers still protected
- Other XSS rules still active
- More granular security control

---

## Conclusion

✅ **Demo Successful:** URL-specific WAF exclusions work exactly as designed.  
🎓 **Educational Value:** Clear demonstration of custom allow rule impact on security.  
⚠️ **Production Caution:** Use managed rule exclusions, not custom allow rules.

## Next Steps

1. Review WAF logs in Log Analytics:
   ```kusto
   AGWFirewallLogs
   | where TimeGenerated > ago(1h)
   | where action_s == "Matched" or action_s == "Blocked"
   | project TimeGenerated, Resource, requestUri_s, action_s, Message, ruleId_s
   | order by TimeGenerated desc
   ```

2. Cleanup resources:
   ```bash
   terraform destroy -auto-approve
   ```
