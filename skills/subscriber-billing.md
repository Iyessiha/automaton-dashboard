---
name: subscriber-billing
description: Invoice active subscribers weekly via x402 micropayments and manage churn
version: 1.0.0
cost_estimate: medium
trust: self
---

# Skill: subscriber-billing

Handle weekly subscriber invoicing via x402, track payment history, and churn non-payers automatically.

## Data files

| File | Purpose |
|---|---|
| `~/data/subscribers.json` | Active subscriber list |
| `~/data/payment_log.json` | Payment history per subscriber |
| `~/data/churn_log.json` | Churned subscriber records |

### subscribers.json schema
```json
[
  {
    "id": "sub_001",
    "wallet": "0xabc123…",
    "relay_address": "0xabc123…@conway.relay",
    "plan": "weekly",
    "price_usdc": 0.50,
    "joined": "2026-09-01T00:00:00Z",
    "last_paid": "2026-10-05T00:00:00Z",
    "failed_attempts": 0,
    "status": "active"
  }
]
```

## When to use

Triggered by heartbeat task `billing-sweep` every Monday at 09:00, or when a new subscriber joins.

## Steps

### 1. Load subscriber list

```python
import json, os
from datetime import datetime, timezone, timedelta

DATA = os.path.expanduser('~/data')
os.makedirs(DATA, exist_ok=True)

subs_path = f'{DATA}/subscribers.json'
log_path  = f'{DATA}/payment_log.json'
churn_path = f'{DATA}/churn_log.json'

def load(path, default):
    try:
        with open(path) as f: return json.load(f)
    except FileNotFoundError: return default

subscribers = load(subs_path, [])
payment_log = load(log_path, {})
churn_log   = load(churn_path, [])

now = datetime.now(timezone.utc)
to_invoice = []

for sub in subscribers:
    if sub['status'] != 'active': continue
    last_paid = datetime.fromisoformat(sub['last_paid']) if sub.get('last_paid') else None
    days_since = (now - last_paid).days if last_paid else 999
    if days_since >= 7:
        to_invoice.append(sub)

print(f"{len(to_invoice)} subscribers due for invoicing")
with open('/tmp/to_invoice.json', 'w') as f:
    json.dump(to_invoice, f)
```

### 2. Invoice each subscriber via x402

For each subscriber in `/tmp/to_invoice.json`, use the x402 tool:

```
Tool: x402_fetch
Args:
  url: https://payment.conway.relay/collect
  method: POST
  body:
    from: {subscriber.wallet}
    to: {MY_WALLET_ADDRESS}
    amount: {subscriber.price_usdc}
    currency: USDC
    memo: "ResearchBot weekly digest - {WEEK_LABEL}"
    idempotency_key: "billing-{subscriber.id}-{WEEK_ISO}"
```

Where `WEEK_ISO` = `datetime.now().strftime('%Y-W%W')` — this prevents double-billing if the skill runs twice.

### 3. Record payment result

```python
results = []  # populated from x402 responses above

for sub, result in zip(to_invoice, results):
    sub_id = sub['id']
    if sub_id not in payment_log:
        payment_log[sub_id] = []

    if result.get('success'):
        payment_log[sub_id].append({
            'week': WEEK_ISO,
            'amount': sub['price_usdc'],
            'tx_hash': result.get('tx_hash'),
            'ts': now.isoformat()
        })
        # Update subscriber record
        sub['last_paid'] = now.isoformat()
        sub['failed_attempts'] = 0
        print(f"✓ Invoiced {sub_id} ${sub['price_usdc']}")
    else:
        sub['failed_attempts'] = sub.get('failed_attempts', 0) + 1
        print(f"✗ Payment failed for {sub_id} (attempt {sub['failed_attempts']})")

# Persist
with open(subs_path, 'w') as f:
    json.dump(subscribers, f, indent=2)
with open(log_path, 'w') as f:
    json.dump(payment_log, f, indent=2)
```

### 4. Churn non-payers

```python
CHURN_AFTER_FAILURES = 3

churned_this_run = []
for sub in subscribers:
    if sub.get('failed_attempts', 0) >= CHURN_AFTER_FAILURES:
        sub['status'] = 'churned'
        sub['churned_at'] = now.isoformat()
        churn_log.append({
            'id': sub['id'],
            'wallet': sub['wallet'],
            'reason': 'payment_failure',
            'failed_attempts': sub['failed_attempts'],
            'churned_at': sub['churned_at']
        })
        churned_this_run.append(sub['id'])
        print(f"⚠ Churned {sub['id']} after {sub['failed_attempts']} failures")

with open(subs_path, 'w') as f:
    json.dump(subscribers, f, indent=2)
with open(churn_path, 'w') as f:
    json.dump(churn_log, f, indent=2)
```

### 5. Warn subscribers with 1 failed attempt

For each subscriber with `failed_attempts == 1`, send a payment reminder via relay:

```
Tool: send_message
Args:
  to: {subscriber.relay_address}
  message: |
    ⚠ Your weekly digest payment of $0.50 USDC failed.
    Please ensure your wallet has sufficient balance.
    You have 2 more attempts before your subscription is paused.
    Wallet: {MY_WALLET_ADDRESS}
```

### 6. Summary report

```python
active  = sum(1 for s in subscribers if s['status'] == 'active')
invoiced = len([r for r in results if r.get('success')])
revenue  = sum(s['price_usdc'] for s, r in zip(to_invoice, results) if r.get('success'))
churned  = len(churned_this_run)

print(f"""
=== Billing sweep complete ===
Active subscribers : {active}
Invoiced this week : {invoiced}
Revenue collected  : ${revenue:.2f} USDC
Churned            : {churned}
==============================
""")
```

Store summary in episodic memory:
```
Tool: memory_store
Args:
  tier: episodic
  content: "Billing sweep {WEEK_ISO}: invoiced {invoiced} subs, collected ${revenue:.2f}, churned {churned}"
  importance: 0.8
```

## New subscriber onboarding

When an agent receives a relay message containing "subscribe" or "subscribe:weekly":

1. Parse wallet address from the message
2. Add to `subscribers.json` with `status: "active"`, `failed_attempts: 0`, `last_paid: null`
3. Send welcome message with first digest attached
4. Invoice immediately for the first week

## Revenue projection

| Subscribers | Weekly | Monthly |
|---|---|---|
| 10 | $5.00 | ~$21.67 |
| 50 | $25.00 | ~$108 |
| 200 | $100.00 | ~$433 |
| 1000 | $500.00 | ~$2,167 |

At $0.05/day compute cost per agent, break-even is **~7 active subscribers**.
