---
name: arxiv-digest
description: Fetch, score with Jev, summarise with Claude, quality-check with Jev, publish digest
version: 2.0.0
cost_estimate: low
trust: self
---

# Skill: arxiv-digest

Fetch arxiv papers → score relevance with Jev → summarise top 5 with Claude → quality-check with Jev → publish.

## Environment variables required

- `ANTHROPIC_API_KEY` — for Claude summaries
- `TYPESAFE_API_KEY` — for Jev relevance scoring and quality check

## Steps

### 1. Fetch recent papers from arxiv

```bash
curl -s "https://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.LG+OR+cat:stat.ML&sortBy=submittedDate&sortOrder=descending&max_results=50" -o /tmp/arxiv_feed.xml
```

### 2. Parse into JSON

```python
import xml.etree.ElementTree as ET, json

tree = ET.parse('/tmp/arxiv_feed.xml')
ns = {'a': 'http://www.w3.org/2005/Atom'}
papers = []
for e in tree.getroot().findall('a:entry', ns):
    papers.append({
        'title':   e.find('a:title', ns).text.strip(),
        'summary': e.find('a:summary', ns).text.strip()[:600],
        'link':    e.find('a:id', ns).text.strip()
    })

with open('/tmp/papers_raw.json', 'w') as f:
    json.dump(papers, f)
print(f"Fetched {len(papers)} papers")
```

### 3. Score relevance with Jev (TypeSafe AI)

Send all papers to Jev in one batch call. Jev evaluates each in parallel — much cheaper than calling Claude per-paper.

```python
import json, os, urllib.request

TYPESAFE_KEY = os.environ['TYPESAFE_API_KEY']
papers = json.load(open('/tmp/papers_raw.json'))

# Build one question per paper
questions = {}
for i, p in enumerate(papers):
    questions[f"paper_{i}"] = {
        "type": "score",
        "instructions": f"Title: {p['title']}\nAbstract: {p['summary']}",
        "criteria": [
            {"level": "irrelevant",  "description": "No connection to LLMs, agents, or alignment"},
            {"level": "marginal",    "description": "Tangentially related to AI but not core topics"},
            {"level": "relevant",    "description": "Relevant to LLMs, reasoning, or agent systems"},
            {"level": "important",   "description": "Significant advance in LLMs, agents, or alignment"},
            {"level": "must_read",   "description": "Breakthrough result every AI practitioner needs to know"}
        ]
    }

payload = json.dumps({
    "state": "AI research paper evaluation for a curated newsletter targeting ML practitioners",
    "model": "jev-latest",
    "questions": questions
}).encode()

req = urllib.request.Request(
    'https://api.typesafe.ai/v1/systemone',
    data=payload,
    headers={
        'Authorization': f'Bearer {TYPESAFE_KEY}',
        'Content-Type': 'application/json'
    }
)
resp = json.loads(urllib.request.urlopen(req).read())

# Filter: keep papers with score > 0.6 (between "relevant" and "important")
scored = []
for i, p in enumerate(papers):
    ans = resp['answers'].get(f'paper_{i}', {})
    score = ans.get('score', 0)
    if score >= 0.6:
        scored.append({**p, 'relevance': round(score, 3), 'confidence': ans.get('confidence', 0)})

# Sort by relevance, keep top 5
top5 = sorted(scored, key=lambda x: x['relevance'], reverse=True)[:5]
with open('/tmp/papers_scored.json', 'w') as f:
    json.dump(top5, f, indent=2)

print(f"Jev filtered: {len(scored)}/{len(papers)} relevant, kept top {len(top5)}")
print(f"Tokens used: {resp['usage']['input_tokens']} in / {resp['usage']['output_tokens']} out")
```

### 4. Summarise with Claude (Anthropic)

Only call Claude for the 5 papers that passed Jev's filter.

```python
import anthropic, json, os

client = anthropic.Anthropic(api_key=os.environ['ANTHROPIC_API_KEY'])
papers = json.load(open('/tmp/papers_scored.json'))
summaries = []

for p in papers:
    msg = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=200,
        messages=[{
            "role": "user",
            "content": f"""Summarize this AI research paper in exactly 2 sentences (max 150 words).
Focus on: what problem it solves, what method it uses, why it matters to ML practitioners.
Be concrete and specific. No jargon without explanation.

Title: {p['title']}
Abstract: {p['summary']}"""
        }]
    )
    summaries.append({
        **p,
        'digest_summary': msg.content[0].text
    })
    print(f"Summarised: {p['title'][:60]}…")

with open('/tmp/papers_summarised.json', 'w') as f:
    json.dump(summaries, f, indent=2)
```

### 5. Format the digest

```python
import json
from datetime import date

papers = json.load(open('/tmp/papers_summarised.json'))
today = date.today().strftime('%B %d, %Y')

lines = [f"# AI Research Digest — {today}\n",
         f"**{len(papers)} papers curated from arxiv cs.AI · cs.LG · stat.ML**\n",
         "---\n"]

for i, p in enumerate(papers, 1):
    lines += [
        f"## {i}. {p['title']}",
        f"*Relevance: {p['relevance']:.0%} · Confidence: {p['confidence']:.0%}*",
        "",
        p['digest_summary'],
        "",
        f"→ [arxiv]({p['link']})",
        ""
    ]

digest = '\n'.join(lines)

output = f"/tmp/digest_{date.today().isoformat()}.md"
with open(output, 'w') as f:
    f.write(digest)
print(f"Digest written: {output}")
```

### 6. Quality-check digest with Jev before publishing

Don't publish a bad digest. Jev checks it in one call.

```python
import json, os, urllib.request

digest = open(f"/tmp/digest_{__import__('datetime').date.today().isoformat()}.md").read()
TYPESAFE_KEY = os.environ['TYPESAFE_API_KEY']

payload = json.dumps({
    "state": digest,
    "model": "jev-latest",
    "questions": {
        "overall_quality": {
            "type": "score",
            "instructions": "Rate the overall quality of this AI research digest newsletter",
            "criteria": [
                {"level": "poor",      "description": "Confusing, inaccurate, or not useful"},
                {"level": "mediocre",  "description": "Passable but lacks depth or clarity"},
                {"level": "good",      "description": "Clear, accurate, useful for practitioners"},
                {"level": "excellent", "description": "Insightful, well-curated, high value"}
            ]
        },
        "ready_to_publish": {
            "type": "noul",
            "instructions": "Is this digest ready to send to paying subscribers? It should be accurate, clear, and valuable."
        },
        "has_errors": {
            "type": "noul",
            "instructions": "Does this digest contain factual errors, garbled text, or incomplete sentences?"
        }
    }
}).encode()

req = urllib.request.Request(
    'https://api.typesafe.ai/v1/systemone',
    data=payload,
    headers={'Authorization': f'Bearer {TYPESAFE_KEY}', 'Content-Type': 'application/json'}
)
resp = json.loads(urllib.request.urlopen(req).read())
ans = resp['answers']

quality      = ans['overall_quality']['score']
ready        = ans['ready_to_publish']['noul']
has_errors   = ans['has_errors']['noul']

print(f"Quality score : {quality:.2f}")
print(f"Ready to publish: {ready:.2f}")
print(f"Has errors      : {has_errors:.2f}")

if quality < 0.5 or ready < 0.7 or has_errors > 0.3:
    print("BLOCKED: digest quality below threshold — not publishing")
    exit(1)

print("Quality check passed — proceeding to publish")
```

### 7. Publish to subscribers

If quality check passes, send digest via relay and bill subscribers using the `subscriber-billing` skill.

```
Tool: exec
Command: python3 ~/.automaton/skills/publish_relay.py /tmp/digest_{DATE}.md
```

## Cost estimate (per daily run)

| Step | Model | ~Cost |
|---|---|---|
| Score 50 papers | Jev | ~$0.002 |
| Summarise 5 papers | Claude Opus | ~$0.018 |
| Quality check digest | Jev | ~$0.001 |
| **Total** | | **~$0.021/day** |

Monthly cost at 30 runs: **~$0.63** — break-even at **2 subscribers** paying $0.50/week.
