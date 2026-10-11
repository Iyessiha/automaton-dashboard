---
name: arxiv-digest
description: Fetch, filter and summarize recent AI/ML papers from arxiv
version: 1.0.0
cost_estimate: low
trust: self
---

# Skill: arxiv-digest

Fetch, filter, and summarize the most relevant AI/ML papers from arxiv for daily digest delivery.

## When to use

Use this skill at the start of each daily digest cycle, or when triggered by a heartbeat `daily-research` task.

## Steps

### 1. Fetch recent papers

```bash
curl -s "https://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.LG+OR+cat:stat.ML&sortBy=submittedDate&sortOrder=descending&max_results=50" -o /tmp/arxiv_feed.xml
```

### 2. Parse and filter

```python
import xml.etree.ElementTree as ET

tree = ET.parse('/tmp/arxiv_feed.xml')
root = tree.getroot()
ns = {'atom': 'http://www.w3.org/2005/Atom'}

KEYWORDS = [
    'large language model', 'llm', 'agent', 'reasoning', 'alignment',
    'instruction tuning', 'rlhf', 'chain-of-thought', 'tool use',
    'autonomous', 'self-improving', 'emergent'
]

papers = []
for entry in root.findall('atom:entry', ns):
    title = entry.find('atom:title', ns).text.strip()
    summary = entry.find('atom:summary', ns).text.strip()
    link = entry.find('atom:id', ns).text.strip()
    combined = (title + ' ' + summary).lower()
    score = sum(1 for kw in KEYWORDS if kw in combined)
    if score > 0:
        papers.append({'title': title, 'summary': summary, 'link': link, 'score': score})

papers.sort(key=lambda p: p['score'], reverse=True)
top5 = papers[:5]

import json
with open('/tmp/filtered_papers.json', 'w') as f:
    json.dump(top5, f)

print(f"Found {len(papers)} relevant papers, keeping top {len(top5)}")
```

### 3. Summarize with inference

For each paper in `/tmp/filtered_papers.json`, call inference with:

```
Summarize this AI research paper in exactly 2 sentences (max 150 words).
Focus on: what problem it solves, what method it uses, why it matters.
Be concrete, avoid jargon.

Title: {title}
Abstract: {summary}
```

Write all summaries to `/tmp/digest_draft.md`.

### 4. Format digest

```markdown
# AI Research Digest — {TODAY}

**{N} papers curated from {TOTAL} submissions**

---

## 1. {TITLE}
{SUMMARY}
→ [arxiv link]

## 2. ...
```

Save to `~/reports/digest_{DATE}.md`.

### 5. Publish to subscribers

Send the digest content as a signed message via the social relay to all subscribers in `~/data/subscribers.json`.

Then invoice each subscriber $0.50 via x402 if their weekly payment is due (check `~/data/payment_log.json`).

## Error handling

- If arxiv is unavailable: use cached feed from yesterday if < 24h old, else skip and notify subscribers of delay
- If inference budget exceeded: reduce to top 3 papers
- If a subscriber payment fails 3 times: mark as `churned`, remove from list, log to `~/data/churn_log.json`

## Output

- `~/reports/digest_{DATE}.md` — the formatted digest
- `~/data/payment_log.json` — updated payment records
- Relay messages sent to all active subscribers
