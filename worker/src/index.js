// Bite — Cloudflare Worker proxy for Google Places API (New)
// Hides the API key, applies rating filter, normalizes data, caches aggressively.

import { handleNearby } from './nearby.js';
import { handlePlace } from './place.js';
import { handlePhoto } from './photo.js';
import { handleGeocode, handleReverseGeocode } from './geocode.js';
import { withCors, preflightResponse, isAllowedOrigin } from './cors.js';
import { checkRateLimit } from './ratelimit.js';
import { jsonError } from './http.js';

export default {
  async fetch(request, env, ctx) {
    // 1. CORS preflight
    if (request.method === 'OPTIONS') {
      return preflightResponse(request, env);
    }

    // 2. Reject disallowed origins early (browsers only — server-to-server requests have no Origin)
    const origin = request.headers.get('Origin');
    if (origin && !isAllowedOrigin(origin, env)) {
      return new Response('Forbidden', { status: 403 });
    }

    // 3. Rate limit (60 req/min per IP)
    const limited = await checkRateLimit(request, env);
    if (limited) return withCors(limited, request, env);

    // 4. Route
    const url = new URL(request.url);
    const path = url.pathname;
    let response;

    try {
      if (path === '/health') {
        response = new Response(JSON.stringify({ ok: true, ts: Date.now() }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' }
        });
      } else if (path === '/api/nearby' && request.method === 'GET') {
        response = await handleNearby(request, env, ctx);
      } else if (path.startsWith('/api/place/') && request.method === 'GET') {
        const id = decodeURIComponent(path.slice('/api/place/'.length));
        response = await handlePlace(id, request, env, ctx);
      } else if (path.startsWith('/api/photo/') && request.method === 'GET') {
        const ref = decodeURIComponent(path.slice('/api/photo/'.length));
        response = await handlePhoto(ref, request, env, ctx);
      } else if (path === '/api/geocode' && request.method === 'GET') {
        response = await handleGeocode(request, env, ctx);
      } else if (path === '/api/reverse-geocode' && request.method === 'GET') {
        response = await handleReverseGeocode(request, env, ctx);
      } else {
        response = jsonError('Not found', 404);
      }
    } catch (err) {
      console.error('Worker error:', err.stack || err);
      response = jsonError("Bite can't reach the kitchen. Try again?", 500);
    }

    return withCors(response, request, env);
  }
};
