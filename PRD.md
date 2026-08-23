# PRD — WA Hot Lead Scorer (Rebuild Spec for agy)

status: PREPARED (rebuild spec, not stakeholder-accepted, not executed)
owner: rauf (decision authority)
built_for: Antigravity (agy) builder — implements plan.md exactly, no scope expansion
narrative_source: /opt/data/wiki/automation/prd-wa-hot-lead-scorer.md (read for problem framing, do not duplicate)
related: wa-hot-lead-scorer-plan-v2.md, wa-hot-lead-scorer-verification.md, wa-hot-lead-scorer-prod-audit.md

## 1. Problem (one line)
Meta Ads drive interest that continues on WhatsApp where it is invisible to the ad system, so hot leads are never scored, surfaced to sales, or (gated) signaled back to Meta.

## 2. Users & outcome
- Primary user: business operator running Meta Ads + WhatsApp sales (rauf).
- Secondary user: sales handler who needs hot-lead alerts.
- Outcome: a WhatsApp conversation showing buying intent is scored (hot/warm/cold) in Bahasa Indonesia; hot leads alert sales and (only after separate approval) send a QualifiedLead event to the Meta Conversions API.

## 3. Goals
1. Ingest WhatsApp messages (inbound + outbound) via WAHA webhook into n8n.
2. Normalize + dedupe by `payload.id`.
3. Rebuild per-sender conversation context (last 20 messages).
4. Score lead temperature in Bahasa Indonesia (rule layer + LLM fallback).
5. Route hot leads to a sales alert; log warm/cold.
6. (Gated, disabled by default) Send QualifiedLead to Meta Conversions API with hashed PII only.

## 4. Non-goals
- Not an official WhatsApp Business API integration (unofficial WAHA, ban risk).
- Not auto-replying to customers (read/score/notify only).
- Not a CRM (JSONL prototype store; production datastore is a later decision).
- Not deploying to production on a business number until validated (test number only).
- Not sending any Meta event in this build (Meta node ships disabled).

## 5. Functional requirements
- FR1: WAHA `message.any` webhook POSTs to n8n `POST /webhook/wa-hotlead`; payload HMAC-SHA512 verified in n8n before any processing.
- FR2: Normalize `payload.*` to sender (strip `@c.us`), message (`payload.body`), direction (inbound when `payload.fromMe` is false, else outbound), timestamp (`payload.timestamp`), `message_id` (`payload.id`).
- FR3: Dedupe by `payload.id`; persist to local JSONL; never score the same id twice.
- FR4: Rebuild last 20 messages per sender as transcript tagged `Cust:`/`Biz:`.
- FR5: Score via indonesian-rules.json dictionary; warm>=20, hot>=60; intent-question boost when price/kirim/beli co-occur with `?` or `kak`/`min`.
- FR6: LLM fallback node for ambiguous/code-switching chats using scoring/llm-classify-prompt.md (JSON-only output).
- FR7: Hot -> Notify Sales (placeholder sink) + disabled Meta node.
- FR8: Warm/Cold -> log (placeholder sink).
- FR9: Every scored lead (hot/warm/cold) -> append one row to a Google Sheet ("Leads" tab) via OAuth-authorized Google Sheets node, columns: sender, message, score, lead_level, signals, direction, timestamp, message_id. Operator authorizes the OAuth credential in the n8n UI; workflow ships with `documentId` placeholder.

## 6. Non-functional requirements
- NF1: Webhook auth via HMAC-SHA512; secret in n8n env `WAHA_HMAC_SECRET`, never in chat or committed.
- NF2: WAHA bound to `127.0.0.1:3000` only (not public).
- NF3: PII stays local; only hashed `ph`/`em` (SHA256) sent to Meta, and only when enabled.
  - OVERRIDE (2026-08-21, owner rauf): FR9 writes raw sender phone + message text to a Google Sheet. This is a conscious exception to NF3 (PII egress to Google), accepted by the decision owner. If this is unwanted later, switch FR9 to redacted/minimal columns.
- NF4: Idempotent per `message_id`.
- NF5: WAHA webhook retry (exponential, 5 attempts) configured in start-session.sh.

## 7. Dependencies
- Docker daemon (WAHA container).
- n8n self-hosted at `127.0.0.1:5678`.
- WAHA session `default` paired on a TEST WhatsApp number (QR route `/api/default/auth/qr?format=image`).
- LLM provider (open: local vs cloud) for FR6.
- Meta Pixel ID + token (open; only for the gated Phase, placeholders in JSON).

## 8. Risks (honest)
- WAHA unofficial client -> account ban: High. Mitigation: test number only, monitoring. Status: Open.
- Rule scorer under-scores intent (e.g. `kirim aja 2`): Med. Mitigation: LLM fallback + threshold at warm>=20. Status: Open.
- HMAC secret leak -> forged events: Med. Mitigation: 600 perms, rotate, strict verify. Status: Mitigated.
- JSONL store not concurrent-safe at scale: Med. Mitigation: DB later. Status: Open.
- WAHA HMAC algorithm support: Low. Verify WAHA emits SHA512; if not, report, do not silently downgrade. Status: Open.

## 9. Acceptance gates
- Gate 0 (infra): docker-compose valid, n8n HMAC secret set, WAHA image pullable. Build-time: JSON/compose/syntax checks pass.
- Gate 1 (pair + ingest, operator): test number CONNECTED; 1 inbound + 1 outbound stored; dedupe confirmed.
- Gate 2 (score quality, operator): thresholds tuned on real chats; LLM provider chosen; real notify sink.
- Gate 3 (validate, operator): hot/warm/cold matches sales review on >=10 samples.
- Gate 4 (Meta, separate approval): Pixel ID + token filled; QualifiedLead sent on hot only; hashed PII. Disabled until then.

## 10. Open decisions
1. WAHA HMAC algorithm: spec requires SHA512; confirm WAHA honors it (see Risk). Owner: rauf/agy report.
2. Threshold correction: prior artifacts used warm>=30; this rebuild canonicalizes warm>=20, hot>=60 to fix under-scoring. Owner: rauf (accepted in rebuild spec).
3. LLM provider for fallback (local Ollama vs cloud; cost/latency).
4. Real notify sink (Telegram/Discord/email).
5. Production datastore (SQLite now vs Postgres).
6. Hot-threshold precision bar owner (proposed >=80% on 30-conversation sample).

This PRD is prepared planning, not execution acceptance.
