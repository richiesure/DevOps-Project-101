#!/bin/bash
set -e

# --------------------------
# Update system packages
# --------------------------
yum update -y

# --------------------------
# Install Java 11
# --------------------------
amazon-linux-extras enable java-openjdk11 -y
yum install -y java-11-openjdk wget tomcat

# --------------------------
# Start and enable Tomcat
# --------------------------
systemctl enable tomcat
systemctl start tomcat

# --------------------------
# Deploy your WAR as ROOT
# --------------------------
wget -O /usr/share/tomcat/webapps/ROOT.war \
  https://github.com/richiesure/DevOps-Project-101/releases/download/v1.0.0/dptweb-1.0.war

# --------------------------
# Restart Tomcat to pick up the WAR
# --------------------------
systemctl restart tomcat
