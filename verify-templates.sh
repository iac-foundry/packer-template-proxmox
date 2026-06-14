#!/bin/bash
set -e

# Verification script for Packer templates
# Run this from inside the bootstrap container to validate the templates work

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPTDIR"

echo "=== Packer Template Verification ==="
echo "Location: $(pwd)"
echo

# Check Packer is available
if ! command -v packer &> /dev/null; then
    echo "❌ Packer not found. Ensure you're running inside the bootstrap container."
    exit 1
fi

echo "✅ Packer found: $(packer version | head -1)"
echo

# Check environment variables
if [ -z "$PROXMOX_URL" ] || [ -z "$PROXMOX_USER" ] || [ -z "$PROXMOX_PASSWORD" ]; then
    echo "⚠️  Environment variables not fully set. Packer validation will work, but builds will fail."
    echo "   Expected: PROXMOX_URL, PROXMOX_USER, PROXMOX_PASSWORD"
else
    echo "✅ Proxmox credentials loaded from environment"
fi
echo

# Step 1: Initialize Packer
echo "Step 1/3: Initializing Packer..."
if packer init proxmox/ > /tmp/packer-init.log 2>&1; then
    echo "✅ Packer init successful"
else
    echo "❌ Packer init failed. See /tmp/packer-init.log"
    cat /tmp/packer-init.log
    exit 1
fi
echo

# Step 2: Validate ubuntu-base template
echo "Step 2/2: Validating ubuntu-base template..."
if packer validate \
    -var-file=ubuntu-22.04.pkrvars.hcl.example \
    proxmox/ > /tmp/packer-validate-base.log 2>&1; then
    echo "✅ Ubuntu-base template validation successful"
else
    echo "❌ Ubuntu-base template validation failed. See /tmp/packer-validate-base.log"
    cat /tmp/packer-validate-base.log
    exit 1
fi
echo

echo "=== All Verifications Passed ✅ ==="
echo
echo "Next steps:"
echo "1. Create your Proxmox variable files from the examples:"
echo "   cp ubuntu-22.04.pkrvars.hcl.example ubuntu-22.04.pkrvars.hcl"
echo "   cp ubuntu-24.04.pkrvars.hcl.example ubuntu-24.04.pkrvars.hcl"
echo
echo "2. Edit the .pkrvars.hcl files with your Proxmox details"
echo
echo "3. Run a build:"
echo "   packer build -var-file=ubuntu-22.04.pkrvars.hcl proxmox/"
echo
echo "See PHASE_1_RUNBOOK.md for detailed instructions."
