#!/bin/bash
#
# Auto-update GitHub secret when VM IP changes
# Run this script periodically (e.g., in cron) or after VM restart
#
# Usage: ./update-github-ip-secret.sh
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - GCP SDK installed and authenticated
#   - gh and gcloud in PATH

set -e

# Configuration
REPO="Reptilefury/blnk-apisix-gateway"
VM_NAME="blnk-gateway"
VM_ZONE="us-central1-a"
PROJECT_ID="heroic-equinox-474616-i5"
SECRET_NAME="GATEWAY_VM_IP"

echo "=== GitHub IP Secret Auto-Update Script ==="
echo "Timestamp: $(date)"
echo ""

# Get current IP from GCP
echo "Fetching current VM IP from GCP..."
CURRENT_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$VM_ZONE" \
  --project="$PROJECT_ID" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

if [ -z "$CURRENT_IP" ]; then
  echo "ERROR: Could not fetch VM IP from GCP"
  echo "Make sure VM is running and has a public IP address"
  exit 1
fi

echo "Current VM IP: $CURRENT_IP"
echo ""

# Get existing secret value from GitHub
echo "Fetching existing secret from GitHub..."
EXISTING_SECRET=$(gh secret list -R "$REPO" --json name,updatedAt -q '.[] | select(.name=="'$SECRET_NAME'") | .name' 2>/dev/null)

if [ -z "$EXISTING_SECRET" ]; then
  echo "ERROR: Secret $SECRET_NAME not found in repository"
  exit 1
fi

echo "Secret found: $SECRET_NAME"
echo ""

# Update secret if IP changed
echo "Updating GitHub secret with new IP..."
echo "$CURRENT_IP" | gh secret set "$SECRET_NAME" -R "$REPO" 2>/dev/null

echo ""
echo "✓ Secret updated successfully!"
echo "✓ GitHub workflows will now use IP: $CURRENT_IP"
echo ""
echo "=== Update Complete ==="
