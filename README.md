# Automaton Console

A monitoring dashboard for [Conway Automaton](https://github.com/Conway-Research/automaton) agents — deploy once on Vercel, connect any number of agents.

![Dashboard showing agent status, live activity log, credit balance, and P&L](https://placehold.co/1200x630/070c16/0fd9a4?text=Automaton+Console)

## Features

- **Live activity log** — streams agent turns, tool calls, and heartbeat events in real time
- **Credit gauge** — sparkline of balance history with survival tier indicator (normal / low_compute / critical)
- **P&L breakdown** — revenue earned vs compute + relay spend, per agent
- **Heartbeat tasks** — last-run timestamps and status for every scheduled task
- **Child agents** — monitor spawned sub-agents and their credit balances
- **Fund button** — top up an agent's credit balance directly from the UI
- **Multi-agent tabs** — switch between agents in a single dashboard
- **CORS proxy** — built-in Vercel serverless function that forwards calls to `api.conway.ai`, so your API key stays server-side

---

## Deploy to Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/YOUR_USERNAME/automaton-dashboard)

Or manually:

```bash
git clone https://github.com/YOUR_USERNAME/automaton-dashboard
cd automaton-dashboard
npx vercel --prod
```

No build step required — `index.html` is served as a static file, `api/conway.js` runs as a serverless function.

---

## Connect your agent

1. Open the deployed URL
2. Click **⚙ Connect** in the top bar
3. Fill in:

| Field | Where to find it |
|---|---|
| API URL | Pre-filled: `https://your-project.vercel.app/api/conway` |
| API Key | `~/.automaton/automaton.json` → `conwayApiKey` |
| Wallet address | `~/.automaton/automaton.json` → `walletAddress` (optional) |

4. Click **Connect** — the pill changes from `DEMO` to `LIVE`

The proxy forwards your requests server-side, so your API key is never exposed in browser traffic.

---

## Run an agent locally

See [Conway-Research/automaton](https://github.com/Conway-Research/automaton) for the full runtime.

Quick start with the included setup script:

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/automaton-dashboard
cd automaton-dashboard

# Run the setup (installs runtime + skills + local proxy)
bash setup.sh
```

Then start everything:

```bash
bash ~/.automaton/start.sh
```

Services:

| Service | URL |
|---|---|
| Dashboard | http://localhost:8080 |
| Conway proxy | http://localhost:3001 |
| Agent loop | — (background process) |

---

## Included agent config

`automaton.json` ships with a pre-configured **ResearchBot** agent:

- Scrapes arxiv daily (cs.AI, cs.LG, stat.ML)
- Summarises top 5 papers with Claude Opus
- Delivers digest to subscribers via Conway relay
- Bills $0.50/week per subscriber via x402 micropayments
- Self-manages survival: downgrades model when credits < $0.50, sends distress signal when critical

Break-even: **~7 paying subscribers** at $0.05/day compute cost.

---

## Included skills

| Skill | Trigger | What it does |
|---|---|---|
| `arxiv-digest` | Daily 07:00 | Fetch → filter → summarise → publish digest |
| `subscriber-billing` | Monday 09:00 | Invoice subscribers, warn on failure, churn after 3 misses |

Drop additional `.md` skill files into `~/.automaton/skills/` — the agent loads them automatically.

---

## Project structure

```
automaton-dashboard/
  index.html              # Dashboard UI (static)
  api/
    conway.js             # Serverless proxy → api.conway.ai
  vercel.json             # Rewrite rules
  package.json
  setup.sh                # Local dev setup script
  automaton.json          # Agent config (ResearchBot template)
  heartbeat.yml           # Custom heartbeat schedule
  skills/
    arxiv-digest.md
    subscriber-billing.md
```

---

## Demo mode

Without an API key the dashboard runs in **DEMO** mode — three simulated agents with realistic activity streams, credit fluctuations, and revenue ticks. Safe to share as a preview.

---

## License

MIT — fork freely, use commercially.

Built on [Conway-Research/automaton](https://github.com/Conway-Research/automaton) (MIT).
