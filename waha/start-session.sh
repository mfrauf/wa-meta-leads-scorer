#!/usr/bin/env bash
# Start WAHA "default" session with message.any webhook + HMAC + retries.
# Prereq: docker compose up -d, and waha/.env loaded (set -a; source waha/.env; set +a)
set -e

BASE="http://127.0.0.1:3000"
WH_KEY="${WAHA_API_KEY:?set WAHA_API_KEY in waha/.env}"
: "${WAHA_HMAC_SECRET:?WAHA_HMAC_SECRET must be set from waha/.env}"

curl -s -X POST "$BASE/api/sessions" \
  -H "X-Api-Key: $WH_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "default",
    "config": {
      "webhooks": [
        {
          "url": "http://127.0.0.1:5678/webhook/wa-hotlead",
          "events": ["message.any"],
          "hmac": { "key": "'"$WAHA_HMAC_SECRET"'" },
          "retries": { "policy": "exponential", "delaySeconds": 2, "attempts": 5 }
        }
      ]
    }
  }'
echo
echo "Now scan the QR code:"
echo "  GET $BASE/api/default/auth/qr?format=image"
