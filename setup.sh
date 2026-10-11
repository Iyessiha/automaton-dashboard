#!/usr/bin/env bash
# ============================================================
# Automaton B2B Setup — ResearchBot agent + dashboard + proxy
# Usage: bash setup.sh
# Requires: node 20+, npm, git
# ============================================================
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-ResearchBot-1}"
CONWAY_API="https://api.conway.ai"
PROXY_PORT="${PROXY_PORT:-3001}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
DIR="$HOME/.automaton"

echo ""
echo "  ╔══════════════════════════════════╗"
echo "  ║   AUTOMATON SETUP — B2B AGENT    ║"
echo "  ╚══════════════════════════════════╝"
echo ""

# ── 1. Clone runtime ──────────────────────────────────────
if [ ! -d "./automaton" ]; then
  echo "→ Cloning Conway Automaton…"
  git clone https://github.com/Conway-Research/automaton.git
else
  echo "→ automaton/ already exists, pulling latest…"
  git -C ./automaton pull --ff-only
fi

cd automaton
npm install --silent
npm run build --silent
echo "✓ Runtime built"

# ── 2. First-run wizard ────────────────────────────────────
if [ ! -f "$DIR/automaton.json" ]; then
  echo ""
  echo "→ Running first-time setup wizard…"
  echo "  (This creates your wallet + Conway API key)"
  node dist/index.js --setup \
    --name "$AGENT_NAME" \
    --genesis "Research frontier AI papers daily, curate summaries, deliver to paying subscribers via x402"
  echo "✓ Wallet + API key created"
else
  echo "→ Config already exists at $DIR/automaton.json — skipping wizard"
fi

# ── 3. Install skills ──────────────────────────────────────
mkdir -p "$DIR/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for skill in arxiv-digest subscriber-billing; do
  if [ -f "$SCRIPT_DIR/${skill}.md" ]; then
    cp "$SCRIPT_DIR/${skill}.md" "$DIR/skills/"
    echo "✓ Skill installed: ${skill}"
  fi
done

# ── 4. Heartbeat config ────────────────────────────────────
if [ -f "$SCRIPT_DIR/heartbeat.yml" ]; then
  cp "$SCRIPT_DIR/heartbeat.yml" "$DIR/heartbeat.yml"
  echo "✓ Heartbeat config installed"
fi

# ── 5. Conway CORS proxy ───────────────────────────────────
cat > "$DIR/proxy.js" << 'EOF'
// Conway API CORS proxy — runs on localhost:3001
// Forwards requests to api.conway.ai with auth headers intact
const http  = require('http');
const https = require('https');
const url   = require('url');

const PORT      = process.env.PROXY_PORT || 3001;
const CONWAY_API = process.env.CONWAY_API || 'https://api.conway.ai';
const base       = new URL(CONWAY_API);

http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const opts = {
    hostname: base.hostname,
    port: 443,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: base.hostname }
  };

  const proxy = https.request(opts, r => {
    res.writeHead(r.statusCode, r.headers);
    r.pipe(res);
  });

  proxy.on('error', err => {
    console.error('[proxy]', err.message);
    if (!res.headersSent) res.writeHead(502);
    res.end(JSON.stringify({ error: err.message }));
  });

  req.pipe(proxy);
}).listen(PORT, () => {
  console.log(`[proxy] http://localhost:${PORT} → ${CONWAY_API}`);
});
EOF
echo "✓ Proxy script written to $DIR/proxy.js"

# ── 6. Dashboard static server ─────────────────────────────
cat > "$DIR/serve-dashboard.js" << 'EOF'
const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT = process.env.DASHBOARD_PORT || 8080;
const FILE = process.env.DASHBOARD_FILE || path.join(__dirname, 'dashboard.html');

http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    fs.createReadStream(FILE).pipe(res);
  } else {
    res.writeHead(404); res.end('Not found');
  }
}).listen(PORT, () => {
  console.log(`[dashboard] http://localhost:${PORT}`);
});
EOF

# Copy dashboard HTML to ~/.automaton/
if [ -f "$SCRIPT_DIR/automaton-console.html" ]; then
  cp "$SCRIPT_DIR/automaton-console.html" "$DIR/dashboard.html"
  echo "✓ Dashboard copied to $DIR/dashboard.html"
fi

# ── 7. Process manager (start.sh) ─────────────────────────
cat > "$DIR/start.sh" << STARTEOF
#!/usr/bin/env bash
# Start all Automaton services
set -euo pipefail
AGENT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

echo "→ Starting Conway CORS proxy on :${PROXY_PORT}…"
PROXY_PORT=${PROXY_PORT} node "\$AGENT_DIR/proxy.js" &
PROXY_PID=\$!
echo "  PID \$PROXY_PID"

echo "→ Starting dashboard on :${DASHBOARD_PORT}…"
DASHBOARD_PORT=${DASHBOARD_PORT} DASHBOARD_FILE="\$AGENT_DIR/dashboard.html" node "\$AGENT_DIR/serve-dashboard.js" &
DASH_PID=\$!
echo "  PID \$DASH_PID"

echo "→ Starting agent loop…"
AGENT_DIR_LOOP="\$(dirname "\$AGENT_DIR")/automaton"
if [ -d "\$AGENT_DIR_LOOP" ]; then
  node "\$AGENT_DIR_LOOP/dist/index.js" --run &
  AGENT_PID=\$!
  echo "  PID \$AGENT_PID"
fi

echo ""
echo "  ✓ Proxy:      http://localhost:${PROXY_PORT}"
echo "  ✓ Dashboard:  http://localhost:${DASHBOARD_PORT}"
echo ""
echo "  In the dashboard → ⚙ Connect → set API URL to http://localhost:${PROXY_PORT}"
echo "  and paste your Conway API key from \$AGENT_DIR/automaton.json"
echo ""
echo "  Press Ctrl+C to stop all services"

trap 'kill \$PROXY_PID \$DASH_PID \${AGENT_PID:-} 2>/dev/null; exit 0' INT TERM
wait
STARTEOF

chmod +x "$DIR/start.sh"
echo "✓ start.sh created"

# ── 8. Summary ─────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║  SETUP COMPLETE                              ║"
echo "  ╠══════════════════════════════════════════════╣"
echo "  ║  Run agent + dashboard:                      ║"
echo "  ║    bash ~/.automaton/start.sh                ║"
echo "  ║                                              ║"
echo "  ║  Dashboard:   http://localhost:${DASHBOARD_PORT}         ║"
echo "  ║  API proxy:   http://localhost:${PROXY_PORT}          ║"
echo "  ║                                              ║"
echo "  ║  Connect dashboard:                          ║"
echo "  ║    API URL  → http://localhost:${PROXY_PORT}         ║"
echo "  ║    API Key  → see ~/.automaton/automaton.json ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""
