#!/bin/bash

# Update system
apt-get update

# Install nginx
apt-get install -y nginx

# Remove default nginx site
rm -f /etc/nginx/sites-enabled/default

# Create simple nginx config
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.json index.html;
    
    server_name _;
    
    location / {
        add_header Content-Type "application/json" always;
        return 200 '{"message":"Hello World! WAF Test Backend","status":"online","server":"nginx","timestamp":"$time_iso8601"}';
    }
    
    location /test-xss {
        add_header Content-Type "application/json" always;
        return 200 '{"status":"bypassed","message":"XSS bypass test endpoint","timestamp":"$time_iso8601"}';
    }
    
    location /xyz {
        add_header Content-Type "application/json" always;
        return 200 '{"status":"allowed","message":"Always allowed path","timestamp":"$time_iso8601"}';
    }
    
    location /admin/users {
        add_header Content-Type "application/json" always;
        return 200 '{"status":"success","message":"User management endpoint","timestamp":"$time_iso8601"}';
    }
}
EOF

# Enable the site
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# Test nginx configuration
nginx -t

# Start and enable nginx
systemctl enable nginx
systemctl restart nginx

echo "Simple nginx setup complete!"