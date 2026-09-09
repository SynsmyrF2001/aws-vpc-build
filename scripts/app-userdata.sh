#!/bin/bash
# Bootstraps the app instance with a minimal identifiable web page — enough
# to actually curl in Phase 6, not a generic default nginx welcome page.
dnf install -y nginx
echo "<h1>aws-vpc-build app tier</h1><p>Serving from $(hostname -f) in the private subnet.</p>" > /usr/share/nginx/html/index.html
systemctl enable --now nginx
