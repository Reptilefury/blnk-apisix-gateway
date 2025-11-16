#!/bin/bash
#
# VM Startup Hook - Auto-update GitHub secrets after VM restart
# Add this to your VM's startup script or cron to auto-update IP
#
# To install:
# 1. Copy this script to your VM
# 2. Make it executable: chmod +x /home/debian/vm-startup-hook.sh
# 3. Add to /etc/rc.local or cron (e.g., every 5 minutes)
#
# For GCP Compute Engine, use Startup Scripts in VM instance settings
#

set -e

# Get the external IP
GATEWAY_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" \
  -H "Metadata-Flavor: Google" 2>/dev/null)

if [ -z "$GATEWAY_IP" ]; then
  echo "$(date): Failed to get IP from metadata server"
  exit 1
fi

# Update GitHub secret using gh CLI
# Assumes gh is installed and authenticated locally
if command -v gh &> /dev/null; then
  echo "$GATEWAY_IP" | gh secret set GATEWAY_VM_IP -R Reptilefury/blnk-apisix-gateway 2>/dev/null
  echo "$(date): Updated GitHub secret with IP: $GATEWAY_IP"
else
  echo "$(date): gh CLI not found - skipping GitHub secret update"
fi

exit 0
