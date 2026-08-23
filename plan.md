# plan.md — Build Spec for agy (WA Hot Lead Scorer)

You are Antigravity (agy). This file is your exact build contract. Produce the repo file tree below, nothing more. Do not execute, deploy, pair a number, or send any network request to Meta. Planning only.

## 1. Source of truth
- PRD.md in this directory (decision-ready requirements).
- Narrative/context: /opt/data/wiki/automation/prd-wa-hot-lead-scorer.md
- Reference artifacts (field shapes only, DO NOT copy verbatim): /opt/data/wa-hotlead/ (docker-compose.yml, waha/start-session.sh, scoring/indonesian-rules.json, scoring/llm-classify-prompt.md, n8n/workflow-wa-hotlead.json)

## 2. Repo file tree you must produce
```
wa-hot-lead/
  docker-compose.yml
  waha/
    .env.example
    start-session.sh
  n8n/
    workflow-wa-hotlead.json
  scoring/
    indonesian-rules.json
    llm-classify-prompt.md
  README.md
  scripts/
    import-workflow.sh
```
No other files. No subdirectories beyond these.

## 3. Constants (canonical, do not vary)
| Constant | Value |
|---|---|
| Webhook (n8n node path) | `wa-hotlead` |
| Webhook (external URL) | `http://127.0.0.1:5678/webhook/wa-hotlead` |
| WAHA host:port | `127.0.0.1:3000` |
| n8n host:port | `127.0.0.1:5678` |
| HMAC | SHA512, header `X-Webhook-Hmac`, secret env `WAHA_HMAC_SECRET` |
| WAHA QR route | `/api/default/auth/qr?format=image` |
| Thresholds | warm >= 20, hot >= 60, cold < 20 |
| Dedupe key | `payload.id` |
| Conversation window | last 20 messages per sender |
| Meta event (disabled) | `QualifiedLead`, hashed `ph`/`em` only |

## 4. Per-file spec

### docker-compose.yml
- Purpose: run WAHA container, localhost-only.
- Image: `devlikeapro/waha:latest`. container_name `waha`. restart `unless-stopped`.
- Ports: `127.0.0.1:3000:3000` (bind to loopback, never 0.0.0.0).
- Env (values from `.env`, do NOT hardcode secrets): `WAHA_API_KEY`, `WAHA_DASHBOARD_USERNAME`, `WAHA_DASHBOARD_PASSWORD`, `WAHA_PRINT_QR=true`, `WAHA_BASE_URL=http://127.0.0.1:3000`.
- Do NOT set the per-session HMAC here (WAHA global webhook env has no hmac.key field); HMAC is set in start-session.sh.
- Volume: `./waha-data:/app/data`.

### waha/.env.example
- Purpose: document required env for WAHA + HMAC. Placeholders only.
- Keys: `WAHA_API_KEY=`, `WAHA_DASHBOARD_USERNAME=`, `WAHA_DASHBOARD_PASSWORD=`, `WAHA_HMAC_SECRET=` (random 32+ byte secret).
- Add a comment: load with `set -a; source waha/.env; set +a` before start-session.sh.

### waha/start-session.sh
- Purpose: create WAHA `default` session with message.any webhook + HMAC + retries.
- Must POST to `http://127.0.0.1:3000/api/sessions` with `X-Api-Key` header.
- Session config webhooks[0]: url `http://127.0.0.1:5678/webhook/wa-hotlead`, events `["message.any"]`, hmac `{"key": "$WAHA_HMAC_SECRET"}`, retries `{"policy":"exponential","delaySeconds":2,"attempts":5}`.
- Print the QR scan instruction: `GET http://127.0.0.1:3000/api/default/auth/qr?format=image`.
- `set -e`; fail if `WAHA_HMAC_SECRET` unset.

### n8n/workflow-wa-hotlead.json
- Purpose: the scoring pipeline. REBUILD for WAHA payload shape (the reference file reads old bridge flat fields and has NO HMAC node; do not reuse it).
- Must be valid n8n workflow JSON, `"active": false`.
- Nodes (exact set):
  1. `WhatsApp Webhook` (n8n-nodes-base.webhook v2): httpMethod POST, path `wa-hotlead`, responseMode `onReceived`, authentication `none`.
  2. `Verify HMAC` (n8n-nodes-base.code): recompute HMAC-SHA512 over the raw request body using `WAHA_HMAC_SECRET` (n8n env/credential); compare to `X-Webhook-Hmac` header (case-insensitive). On mismatch or missing header, stop execution (throw / return 401). On success, pass parsed payload downstream.
  3. `Normalize & Dedupe` (code): read `payload.id` (message_id), `payload.from` (strip `@c.us`), `payload.body` (message), `payload.timestamp`, `payload.fromMe` (inbound when false). Dedupe by `payload.id` against local JSONL store; append new rows.
  4. `Load Conversation Context` (code): read last 20 messages per sender from store; transcript tagged `Cust:`/`Biz:`.
  5. `Score Lead (ID Rules)` (code): load dictionary from indonesian-rules.json; thresholds warm>=20 hot>=60; intent-question boost when price/kirim/beli co-occur with `?` or `kak`/`min`. Output `score`, `lead_level`, `signals`.
  6. `Is Hot?` (n8n-nodes-base.if): `lead_level == hot`.
  7. `Notify Sales (Hot)` (set/placeholder): build `alert` string `{sender} HOT ({score}): {message}`.
  8. `Send QualifiedLead to Meta (disabled)` (httpRequest, `disabled: true`): url `https://graph.facebook.com/v22.0/REPLACE_PIXEL_ID/events`, Authorization `Bearer REPLACE_ACCESS_TOKEN`, body event_name `QualifiedLead`, action_source `system_generated`. Placeholders only.
  9. `Log Warm/Cold` (set/placeholder): record `lead_level`, `score`.
  10. Optional sticky note documenting the flow.
  11. `Export Lead to Sheet (OAuth)` (n8n-nodes-base.googleSheets, typeVersion 4): fed directly from `Score Lead (ID Rules)` (so hot/warm/cold all land). operation `append`, sheet name `Leads`, columns: sender, message, score, lead_level, signals, direction, timestamp, message_id. Credential reference `googleSheetsOAuth2Api` named "Google Sheets OAuth2". `documentId` placeholder `REPLACE_SHEET_ID` (operator fills in n8n UI). No activation.
- Connections: Webhook -> Verify HMAC -> Normalize & Dedupe -> Load Conversation Context -> Score Lead -> [Is Hot? AND Export Lead to Sheet]; Is Hot? true -> Notify Sales + (disabled) Meta; false -> Log Warm/Cold.

### scoring/indonesian-rules.json
- Purpose: Bahasa Indonesia keyword dictionary for the rule layer.
- Shape: `{ "version", "language":"id", "thresholds": {"hot":60,"warm":20,"cold":0}, "categories": { cat: { "weight": N, "keywords": [...] } }, "notes": "..." }`.
- Categories/weights (carry from reference): harga 10; beli 25; bayar 25; kirim 25; jumlah 15; siap 15. Keep keywords from reference file.
- `thresholds.warm` MUST be 20 (corrects prior 30).

### scoring/llm-classify-prompt.md
- Purpose: LLM fallback prompt (Bahasa, few-shot, JSON-only).
- Carry the reference prompt content (lead_level hot/warm/cold definitions, normalization notes, JSON output schema with lead_level/score/intent/signals/reason). Do not alter the output contract.

### README.md
- Purpose: operator runbook. Status PREPARED/NOT ACTIVATED. List the file tree, the constants table, the gate sequence (Gate 0-4), and the risk note (unofficial WAHA, test number only, no Meta send until approval). Reference PRD.md.

### scripts/import-workflow.sh
- Purpose: import the generated workflow JSON into n8n via the n8n REST API.
- Behavior: `curl -s -X POST http://127.0.0.1:5678/api/v1/workflows --header "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" --data @n8n/workflow-wa-hotlead.json`.
- MUST NOT activate the workflow, MUST NOT modify any other n8n resource. Print the returned workflow id. Fail clearly if `N8N_API_KEY` unset or curl non-200.

## 5. Do NOT do
- Do NOT modify live n8n beyond importing the generated workflow JSON via scripts/import-workflow.sh.
- Do NOT send any Meta Conversions API request (Meta node stays disabled).
- Do NOT pair a real/production WhatsApp number; test number only, and pairing is an operator Gate 1 action, not yours.
- Do NOT invent or hardcode credentials; placeholders only for Pixel ID / access token / API keys.
- Do NOT add nodes, sinks, retries, DB stores, or endpoints beyond the 11-node set above (10 original + Export Lead to Sheet, added 2026-08-21 by owner approval).
- Do NOT expose WAHA or the webhook on 0.0.0.0 or any public interface.
- Do NOT change thresholds from warm>=20 hot>=60.

## 6. Verification commands (run locally, static only)
```
# JSON validity for every .json file
for f in docker-compose.yml n8n/workflow-wa-hotlead.json scoring/indonesian-rules.json; do
  python3 -m json.tool "$f" > /dev/null && echo "OK $f" || echo "FAIL $f"
done

# node syntax check of each Code node's JS (extract jsCode from workflow JSON)
python3 - <<'PY'
import json, subprocess, tempfile, os
wf = json.load(open('n8n/workflow-wa-hotlead.json'))
for n in wf['nodes']:
    js = n.get('parameters',{}).get('jsCode')
    if js:
        with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as t:
            t.write(js); p=t.name
        r = subprocess.run(['node','--check',p], capture_output=True, text=True)
        print(('OK ' if r.returncode==0 else 'FAIL ')+n['name'])
        if r.returncode!=0: print(r.stderr)
        os.unlink(p)
PY

# docker compose config validity (requires Docker; skip if absent)
docker compose -f docker-compose.yml config --quiet && echo "OK compose" || echo "compose check skipped/failed"

# WAHA health (requires WAHA running; operator step, not build)
curl -s -o /dev/null -w "waha_http_%{http_code}\n" http://127.0.0.1:3000/
```

## 7. Handoff
Read PRD.md and plan.md in this directory. Implement them exactly. Do not expand scope.
