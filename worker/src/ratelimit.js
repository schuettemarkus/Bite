// Per-IP sliding-window rate limit using KV.
// 60 requests per minute. KV is eventually consistent across regions,
// so this is "best effort." For hard limits, layer Cloudflare's native
// Rate Limiting Rules on top.

import { jsonError } from './http.js';

const WINDOW_MS = 60_000;
const MAX_REQUESTS = 60;

export async function checkRateLimit(request, env) {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const now = Date.now();
  const key = `rl:${ip}`;

  const stored = await env.CACHE.get(key, { type: 'json' });
  const recent = (stored?.ts || []).filter(t => now - t < WINDOW_MS);

  if (recent.length >= MAX_REQUESTS) {
    const response = jsonError('Slow down a bit. Try again in a minute.', 429);
    response.headers.set('Retry-After', '60');
    return response;
  }

  recent.push(now);
  // Don't await — let it run in background.
  // (Caller should still trigger ctx.waitUntil if strictness is critical.)
  await env.CACHE.put(key, JSON.stringify({ ts: recent }), { expirationTtl: 120 });
  return null;
}
