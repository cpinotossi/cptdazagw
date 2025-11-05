#!/bin/bash

# Update system
apt-get update

# Install nginx
apt-get install -y nginx

# Remove default nginx site
rm -f /etc/nginx/sites-enabled/default
rm -f /var/www/html/index.nginx-debian.html

# Create custom nginx config
cat > /etc/nginx/sites-available/waf-test << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    # Enable access logging for testing
    access_log /var/log/nginx/waf-test.log combined;
    error_log /var/log/nginx/waf-test-error.log;
    
    # Default JSON response - Hello World
    location = / {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"message":"Hello World! WAF Test Backend","status":"online","server":"nginx","purpose":"Azure WAF Custom Rules Demo","timestamp":"$time_iso8601"}';
    }
    
    # Conditional XSS test endpoint - /test-xss
    location /test-xss {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"status":"bypassed","rule_bypassed":"941120","custom_rule":"priority_1_conditional","path":"/test-xss","message":"XSS payload bypassed WAF with waf=off parameter","timestamp":"$time_iso8601"}';
    }
    
    # Always allowed path - /xyz/
    location ^~ /xyz/ {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"status":"allowed","rule_bypassed":"all_managed_rules","custom_rule":"priority_3_always","path":"/xyz/","message":"Path always bypasses WAF","timestamp":"$time_iso8601"}';
    }
    
    # Database endpoint for SQL injection tests
    location /database {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"status":"should_be_blocked","rule_triggered":"custom_priority_4","attack_type":"sql_injection","message":"SQL injection should be blocked by WAF","note":"If you see this, WAF is not working","timestamp":"$time_iso8601"}';
    }
    
    # Search endpoint for XSS tests
    location /search {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"status":"should_be_blocked","rule_triggered":"941120","attack_type":"xss","message":"XSS should be blocked by managed rule","note":"If you see this, WAF is not working","timestamp":"$time_iso8601"}';
    }
    
    # WP-Admin paths
    location ^~ /wp-admin/ {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"status":"should_be_blocked","rule_triggered":"941120","path":"/wp-admin/","message":"Should be blocked when XSS payload present","note":"If you see this, WAF is not working","timestamp":"$time_iso8601"}';
    }
    
    # Catch-all for other requests
    location / {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 200 '{"message":"WAF Test Endpoint","status":"success","path":"$request_uri","server":"nginx","timestamp":"$time_iso8601"}';
    }
}
EOF

# Enable the site
ln -s /etc/nginx/sites-available/waf-test /etc/nginx/sites-enabled/

# Enable the site
ln -s /etc/nginx/sites-available/waf-test /etc/nginx/sites-enabled/

# Create web root directory and ensure proper permissions
mkdir -p /var/www/waf-test
chown -R www-data:www-data /var/www/waf-test

# Remove default HTML directory to avoid conflicts
rm -rf /var/www/html

# Test nginx configuration
nginx -t

# Start nginx
systemctl enable nginx
systemctl start nginx

echo "WAF test web server setup complete!"
echo "Server is running on port 80 with JSON responses"
echo "Test paths configured for:"
echo "  - / (hello world)"
echo "  - /test-xss (conditional bypass)"
echo "  - /xyz/ (always allowed)"
echo "  - /wp-admin/ (should be blocked)"
echo "  - /database (SQL injection tests)"
echo "  - /search (XSS tests)"