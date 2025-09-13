#!/bin/bash
set -e

# ------------------------------
# Update system packages
# ------------------------------
yum update -y

# ------------------------------
# Install Java 11
# ------------------------------
amazon-linux-extras enable java-openjdk11 -y
yum install -y java-11-openjdk wget

# ------------------------------
# Create app directory
# ------------------------------
mkdir -p /opt/java-login-app
cd /opt/java-login-app

# ------------------------------
# Download your pre-built JAR from GitHub
# Replace <GITHUB_JAR_URL> with your actual JAR URL
# ------------------------------
wget -O java-login-app.jar <GITHUB_JAR_URL>

# ------------------------------
# Create systemd service
# ------------------------------
echo "[Unit]
Description=Java Login App
After=network.target

[Service]
ExecStart=/usr/bin/java -jar /opt/java-login-app/java-login-app.jar
Restart=always
User=ec2-user
WorkingDirectory=/opt/java-login-app

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/java-login-app.service

# ------------------------------
# Reload systemd and start the service
# ------------------------------
systemctl daemon-reload
systemctl enable java-login-app
systemctl start java-login-app

# ------------------------------
# Ensure firewall allows 8080 (optional, handled by SG normally)
# ------------------------------
firewall-cmd --add-port=8080/tcp --permanent || true
firewall-cmd --reload || true
