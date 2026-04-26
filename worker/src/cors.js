// CORS — production origin (from env) + localhost for dev.

const LOCALHOST = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export function isAllowedOrigin(origin, env) {
  if (!origin) return false;
  if (LOCALHOST.test(origin)) return true;
  if (env.ALLOWED_ORIGIN && origin === env.ALLOWED_ORIGIN) return true;
  return false;
}

export function preflightResponse(request, env) {
  const origin = request.headers.get('Origin');
  const headers = {
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400'
  };
  if (isAllowedOrigin(origin, env)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Vary'] = 'Origin';
  }
  return new Response(null, { status: 204, headers });
}

export function withCors(response, request, env) {
  const origin = request.headers.get('Origin');
  if (!isAllowedOrigin(origin, env)) return response;
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', origin);
  headers.set('Vary', 'Origin');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}
