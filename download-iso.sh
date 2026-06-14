#!/bin/bash
# Downloads an ISO directly to Proxmox storage using the Proxmox API.
# Proxmox fetches the ISO itself — nothing is re-uploaded from this machine.
#
# Usage:
#   bash download-iso.sh <filename> <url> <sha256checksum>
#
# Example:
#   bash download-iso.sh \
#     ubuntu-24.04.4-live-server-amd64.iso \
#     https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso \
#     e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433

set -euo pipefail

FILENAME="${1:?Usage: $0 <filename> <url> <sha256checksum>}"
URL="${2:?Usage: $0 <filename> <url> <sha256checksum>}"
CHECKSUM="${3:?Usage: $0 <filename> <url> <sha256checksum>}"

: "${PROXMOX_URL:?PROXMOX_URL is not set}"
: "${PROXMOX_USER:?PROXMOX_USER is not set}"
: "${PROXMOX_PASSWORD:?PROXMOX_PASSWORD is not set}"
: "${PROXMOX_ISO_STORAGE:=local}"

API="${PROXMOX_URL%/}/api2/json"

# Resolve node name from Proxmox if PROXMOX_NODE is not set or is the generic default
if [ -z "${PROXMOX_NODE:-}" ]; then
  echo "==> PROXMOX_NODE not set, detecting from cluster..."
fi

echo "==> Authenticating with Proxmox at ${API}..."
AUTH=$(curl -ks -X POST "${API}/access/ticket" \
  -d "username=${PROXMOX_USER}" \
  --data-urlencode "password=${PROXMOX_PASSWORD}")

TICKET=$(echo "$AUTH" | jq -r '.data.ticket // empty')
CSRF=$(echo "$AUTH"   | jq -r '.data.CSRFPreventionToken // empty')

if [ -z "$TICKET" ]; then
  echo "❌ Authentication failed. Response:"
  echo "$AUTH" | jq .
  exit 1
fi
echo "   Authenticated successfully."

# If PROXMOX_NODE not provided, detect it from the cluster nodes list
if [ -z "${PROXMOX_NODE:-}" ]; then
  PROXMOX_NODE=$(curl -ks \
    -b "PVEAuthCookie=${TICKET}" \
    "${API}/nodes" \
    | jq -r '.data[0].node // empty')
  echo "   Detected node: ${PROXMOX_NODE}"
fi

: "${PROXMOX_NODE:?Could not determine PROXMOX_NODE}"

echo "==> Checking if ISO already exists on ${PROXMOX_NODE}/${PROXMOX_ISO_STORAGE}..."
CONTENT=$(curl -ks \
  -b "PVEAuthCookie=${TICKET}" \
  "${API}/nodes/${PROXMOX_NODE}/storage/${PROXMOX_ISO_STORAGE}/content")

EXISTING=$(echo "$CONTENT" | jq -r --arg f "iso/${FILENAME}" '.data[]? | select(.volid | endswith($f)) | .volid')

if [ -n "$EXISTING" ]; then
  echo "✅ ISO already present: ${EXISTING}"
  echo "   Skipping download."
  exit 0
fi

echo "==> Requesting Proxmox to download ISO directly..."
echo "    File:    ${FILENAME}"
echo "    URL:     ${URL}"
echo "    Storage: ${PROXMOX_ISO_STORAGE}"
echo "    Node:    ${PROXMOX_NODE}"

TASK_RESPONSE=$(curl -ks -X POST \
  -b "PVEAuthCookie=${TICKET}" \
  -H "CSRFPreventionToken: ${CSRF}" \
  "${API}/nodes/${PROXMOX_NODE}/storage/${PROXMOX_ISO_STORAGE}/download-url" \
  -d "url=${URL}" \
  -d "filename=${FILENAME}" \
  -d "content=iso" \
  -d "checksum-algorithm=sha256" \
  -d "checksum=${CHECKSUM}")

TASK=$(echo "$TASK_RESPONSE" | jq -r '.data // empty')

if [ -z "$TASK" ]; then
  echo "❌ Failed to start download task. Response:"
  echo "$TASK_RESPONSE" | jq .
  exit 1
fi

echo "==> Download task started: ${TASK}"
echo "    Polling for completion (this may take a few minutes)..."

while true; do
  STATUS_RESPONSE=$(curl -ks \
    -b "PVEAuthCookie=${TICKET}" \
    "${API}/nodes/${PROXMOX_NODE}/tasks/${TASK}/status")

  STATUS=$(echo "$STATUS_RESPONSE"   | jq -r '.data.status // empty')
  EXITCODE=$(echo "$STATUS_RESPONSE" | jq -r '.data.exitstatus // empty')

  if [ "$STATUS" = "stopped" ]; then
    if [ "$EXITCODE" = "OK" ]; then
      echo "✅ ISO downloaded successfully: ${PROXMOX_ISO_STORAGE}:iso/${FILENAME}"
    else
      echo "❌ Download task failed with exit status: ${EXITCODE}"
      curl -ks \
        -b "PVEAuthCookie=${TICKET}" \
        "${API}/nodes/${PROXMOX_NODE}/tasks/${TASK}/log" | jq -r '.data[].t'
      exit 1
    fi
    break
  fi

  printf "    Status: %-20s\r" "${STATUS}"
  sleep 5
done
