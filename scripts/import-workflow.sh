#!/usr/bin/env bash
# Import WA Hot Lead Scorer workflow into n8n via REST API.
# Status: Prepared import script (does NOT activate workflow).
set -euo pipefail

: "${N8N_API_KEY:?Error: N8N_API_KEY environment variable is required}"

N8N_HOST="${N8N_HOST:-http://127.0.0.1:5678}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_FILE="${SCRIPT_DIR}/../n8n/workflow-wa-hotlead.json"

if [ ! -f "$WORKFLOW_FILE" ]; then
  echo "Error: Workflow file not found at $WORKFLOW_FILE" >&2
  exit 1
fi

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${N8N_HOST}/api/v1/workflows" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -H "Content-Type: application/json" \
  --data @"$WORKFLOW_FILE")

HTTP_BODY=$(echo "$RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" -ne 200 ] && [ "$HTTP_CODE" -ne 201 ]; then
  echo "Error: n8n API returned HTTP $HTTP_CODE" >&2
  echo "$HTTP_BODY" >&2
  exit 1
fi

WORKFLOW_ID=$(echo "$HTTP_BODY" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("id", data.get("data", {}).get("id", "UNKNOWN")))')
echo "Successfully imported workflow. ID: $WORKFLOW_ID (inactive)"
