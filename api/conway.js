// Vercel serverless proxy — forwards requests to api.conway.ai
// Deployed at: https://{your-project}.vercel.app/api/conway
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type');

  if (req.method === 'OPTIONS') { res.status(204).end(); return; }

  // Strip /api/conway prefix, forward the rest to Conway API
  const conwayPath = req.url.replace(/^\/api\/conway/, '') || '/';
  const conwayUrl = `https://api.conway.ai${conwayPath}`;

  try {
    const upstream = await fetch(conwayUrl, {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        ...(req.headers.authorization ? { Authorization: req.headers.authorization } : {})
      },
      body: ['POST', 'PUT', 'PATCH'].includes(req.method) ? JSON.stringify(req.body) : undefined
    });

    const contentType = upstream.headers.get('content-type') || '';
    const body = contentType.includes('application/json')
      ? await upstream.json()
      : await upstream.text();

    res.status(upstream.status);
    if (typeof body === 'string') res.send(body);
    else res.json(body);

  } catch (err) {
    res.status(502).json({ error: 'Upstream error', message: err.message });
  }
}
