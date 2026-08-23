# Delivery status — WA Hot Lead Scorer (agy build)

Date: 2026-08-21
Status: BUILT + IMPORTED INACTIVE into VPS n8n. Not activated, no Meta send.

## agy build (local, VPS)
- Repo: /opt/data/projects/wa-hot-lead (git, committed 9e69cd6)
- 8 files: docker-compose.yml, waha/.env.example, waha/start-session.sh, n8n/workflow-wa-hotlead.json, scoring/indonesian-rules.json, scoring/llm-classify-prompt.md, README.md, scripts/import-workflow.sh
- Verified: JSON valid, all Code-node JS passes node --check, compose valid, loopback-only, active:false, Meta node disabled, 10 nodes.

## Imported to VPS n8n (so it can be opened from the VPS)
- Workflow ID: lNnorqofr6QwSG9a
- Name: WA Hot Lead Scorer
- active: false
- nodes: 10
- disabled node: Send QualifiedLead to Meta (disabled)
- Method: stripped read-only "active" field, POST /api/v1/workflows. Inactive by default.

## Note: workflow inventory on VPS n8n (2026-08-21)
- lNnorqofr6QwSG9a "WA Hot Lead Scorer" — agy build, ACTIVE deliverable, inactive, 10 nodes, Meta disabled. KEEP.
- TShPtKwHbDDzpqPW "WA Hot Lead Scorer (WAHA)" — old hand-built v2, ARCHIVED on request (2026-08-21).
- jDLJfehhsl6O9Mdg "WA Hot Lead Scorer (MVP)" — earliest onionj-based build, still unarchived + inactive. Superseded; candidate to archive too.

## To open from VPS
- n8n UI at http://127.0.0.1:5678 (tunnel: ssh -N -L 5678:127.0.0.1:5678 ubuntu@43.134.26.238)
- Workflows > "WA Hot Lead Scorer" > open. Do NOT activate until Gate 1 (test-number QR) done.

## Remaining gates (operator, not agy)
- Gate 1: run waha/start-session.sh (WAHA up + HMAC), scan QR on TEST number.
- Gate 2/3: LLM provider + calibrate on real chats.
- Gate 4: Meta creds + enable node (separate approval).
