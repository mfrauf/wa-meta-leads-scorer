# WA Hot Lead Scorer

**Read WhatsApp leads, score them hot/warm/cold automatically, and send the signal to Meta so you can retarget them with the right campaign.**

Built for marketers who run Click-to-WhatsApp ads. No coding needed to use it — this README explains what it does, how the pieces fit, and how to set it up.

---

## The problem it solves

When people click your ad and message you on WhatsApp, some are ready to buy ("pesan 5 deh"), some are just browsing ("boleh lihat katalog?"). Right now those all look identical to Meta Ads Manager.

This tool reads every incoming WhatsApp message, understands the intent in Bahasa Indonesia, and labels the person **hot**, **warm**, or **cold**. That label becomes a signal to Meta — so your next campaign can:

- Show closing offers only to **hot** leads (ready to buy)
- Show consideration ads (offers, proof) to **warm** leads
- Show educational content to **cold** leads
- Build a **lookalike audience** from your hottest leads to find new customers like them

## How it works (the 60-second version)

```
WhatsApp message
      |
      v
 [WAHA gateway]  -- receives messages from your paired number
      |
      v
 [n8n workflow]  -- the brain, 5 steps:
      |
      |-- 1. Normalize: extract the sender's phone number
      |       (@c.us = real phone -> usable; @lid = hidden number -> skipped)
      |
      |-- 2. Score: an LLM reads the chat and returns hot / warm / cold + a 0-100 score
      |
      |-- 3. Log: every message is written to a Google Sheet (your full history)
      |
      |-- 4. State machine: did this person's level CHANGE since their last message?
      |       no change -> do nothing (no spam)
      |       changed   -> continue
      |
      '--> 5. Meta signal: send LeadHot / LeadWarm / LeadCold event
              with a SHA-256 hashed phone number to Meta's Conversions API
```

## Why "state machine"? (the part most tools get wrong)

Meta audiences are **append-only** — you cannot remove someone from a pool via API. So "moving" a lead from warm to hot doesn't work by deleting anything.

This tool handles it correctly:

1. It remembers each phone's last known level.
2. It only fires a Meta event when the level **changes** (first contact, or upgrade/downgrade).
3. In Meta Ads Manager you then build campaigns with **exclusions**:

| Campaign | Targets | Excludes | Purpose |
|---|---|---|---|
| A - Nurture | LeadCold audience | Warm + Hot | educate cold leads |
| B - Consideration | LeadWarm audience | Hot | move warm → hot |
| C - Close | LeadHot audience | (none) | convert to purchase |
| Lookalike | seeded from LeadHot | — | find new similar buyers |

Result: a person's *effective* pool is always their highest level, enforced by exclusions instead of deletion.

## What you need

| Requirement | Why |
|---|---|
| A VPS or server (2GB RAM+) | runs Docker containers |
| Docker + Docker Compose | runs WAHA + n8n |
| A spare WhatsApp number | WAHA logs in via QR; using your main number carries ban risk |
| OpenRouter account (free) | powers the LLM scoring; free models work, paid is more stable |
| Google account | for the leads spreadsheet export |
| Meta Business account | Pixel ID + Conversions API token (only if you want the Meta signals) |

## Setup

### 1. Start the containers

```bash
docker compose up -d        # starts WAHA (WhatsApp gateway) + n8n
```

### 2. Pair your WhatsApp number

Open `http://YOUR-SERVER:3000` → scan the QR code with the target phone.

### 3. Point WAHA at n8n

In WAHA's session settings, set the webhook to:
```
http://n8n:5678/webhook/wa-hotlead
```
and subscribe to the `message.any` event.

### 4. Import the workflow

Import `n8n/workflow-wa-hotlead.json` into n8n, then set two things in the **Score Lead (LLM)** node:

- Your OpenRouter API key (replace `${OPENROUTER_API_KEY}`)
- Review the model names if your favorites changed (free model slinks rotate often)

### 5. Connect Google Sheets

In n8n, connect a Google Sheets OAuth credential, then edit the **Export Lead to Sheet** node to point at your own spreadsheet. Create a tab named `Leads_Live`.

Columns written: `sender`, `message`, `score`, `lead_level`, `signals`, `direction`, `timestamp`, `message_id`, `meta_matchable`.

### 6. Activate

Flip the workflow to Active in n8n. Send yourself a test message — check the Sheet.

## Turning on the Meta signals (optional)

The Meta node ships **disabled** on purpose. When ready:

1. Get your Pixel ID + Conversions API token from Meta Events Manager.
2. Edit the **Send QualifiedLead to Meta** node: replace `REPLACE_PIXEL_ID` and `REPLACE_ACCESS_TOKEN`.
3. Enable the node.
4. Verify events appear in Events Manager (look for `LeadHot`, `LeadWarm`, `LeadCold`).
5. Create custom audiences from each event name, then build your campaign structure per the table above.

## Closing deals: the Purchase signal (the money event)

Lead events tell Meta *intent*. The `Purchase` event tells Meta *revenue* — the strongest signal Meta's AI optimizer can learn from.

When you close a deal (payment received), send yourself a WhatsApp message from your own number:

```
close 628XXXXXXX01 750000
```

**Format:** `close <customer-phone> <amount>` — amount optional but recommended.

The tool then:
1. Detects your message (only YOUR outbound messages can trigger this, never customer messages)
2. SHA-256 hashes the customer's phone
3. Fires one `Purchase` event to Meta with `value` + `currency: IDR`
4. Dedupes: the same phone can only be closed once (no accidental double-fires)

**Why bother:** with Purchase in your event hierarchy (`LeadCold → LeadWarm → LeadHot → Purchase`), Meta optimizes toward actual revenue instead of chat enthusiasm. Your lookalike audience should also be seeded from purchasers, not just hot leads.

## Files

```
├── docker-compose.yml          # WAHA + n8n containers
├── waha/
│   ├── .env.example            # config template (copy to .env)
│   └── start-session.sh        # QR login helper
├── n8n/
│   └── workflow-wa-hotlead.json  # importable n8n workflow (secrets placeholdered)
├── scoring/
│   ├── llm-classify-prompt.md    # the Bahasa Indonesia classification prompt
│   └── indonesian-rules.json     # legacy keyword rules (kept for reference)
├── scripts/
│   └── import-workflow.sh        # one-shot importer via n8n API
├── docs/
│   └── lead-funnel-meta-audiences.html  # visual diagram of the funnel architecture
├── PRD.md                        # product requirements (detailed spec)
└── plan.md                       # build plan notes
```

## Honest limitations

- **LID numbers**: WhatsApp hides phone numbers behind LIDs (`@lid`) when the sender has privacy enabled. Those leads get scored and logged but **cannot be matched to Meta** — nothing can be done about this at our level; it's a WhatsApp platform restriction.
- **Free LLM models rotate**: free OpenRouter models come and go. The workflow has a fallback chain, but expect occasional maintenance. Paid small models (~$0.0002/lead) remove this entirely.
- **HMAC verification disabled**: n8n mangles raw webhook bodies, breaking signature verification. Mitigation: bind everything to localhost only. If you expose n8n publicly, fix this first.
- **Audience size**: Meta needs roughly 100+ matched people per country before custom-event audiences serve. Early on, events accumulate but don't power targeting yet.
- **Ban risk**: unofficial WhatsApp gateways (WAHA included) carry inherent account-ban risk. Use a dedicated business number, not your personal one.

## FAQ

**Q: Do I need to know how to code?**
No. Setup is copy-paste commands plus clicking through n8n's UI. The workflow JSON imports ready-made.

**Q: Can I change what counts as "hot"?**
Yes — everything lives in `scoring/llm-classify-prompt.md`. Edit the definitions there; the LLM follows that file. No code changes needed.

**Q: What languages does it understand?**
The prompt is tuned for Bahasa Indonesia including casual/slang forms (gak, udh, min, kak). Other languages would need prompt adjustments.

**Q: Does it read my personal chats?**
It processes every message sent to the paired number, including group chats (which are scored but never matched to Meta). Only run this on a dedicated business number.

---

License: MIT · Built with n8n, WAHA, and OpenRouter
