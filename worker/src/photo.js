// /api/photo/{photoName} — proxy Place Photo URLs so the API key never reaches the client.

import { fetchPhotoUri } from './places.js';

const SIGNED_URL_TTL_S = 3000; // 50 min — Google's signed URLs are typically valid 1 hour.
const MAX_WIDTH = 1600;
const DEFAULT_WIDTH = 800;

export async function handlePhoto(photoName, request, env, ctx) {
  // photoName looks like "places/{placeId}/photos/{photoRef}"
  if (!photoName.startsWith('places/') || !photoName.includes('/photos/')) {
    return new Response('Invalid photo reference', { status: 400 });
  }

  const url = new URL(request.url);
  const requested = parseInt(url.searchParams.get('maxWidth'), 10) || DEFAULT_WIDTH;
  const maxWidth = Math.min(Math.max(requested, 200), MAX_WIDTH);

  const cacheKey = `photo:${photoName}:${maxWidth}`;
  let photoUri = await env.CACHE.get(cacheKey);

  if (!photoUri) {
    photoUri = await fetchPhotoUri(photoName, maxWidth, env);
    if (!photoUri) {
      return new Response('Photo not available', { status: 404 });
    }
    ctx.waitUntil(
      env.CACHE.put(cacheKey, photoUri, { expirationTtl: SIGNED_URL_TTL_S })
    );
  }

  // 302 to the signed Google URL; browser caches the actual image.
  // The signed URL doesn't contain our API key — safe to expose.
  return Response.redirect(photoUri, 302);
}
