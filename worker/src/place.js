// /api/place/{placeId} — full details for the match view.
// Lazy-loaded only when a restaurant is surfaced; keeps Nearby calls cheap.

import { fetchPlaceDetails } from './places.js';
import { jsonOk, jsonError } from './http.js';

const FIELD_MASK = [
  'id',
  'displayName',
  'location',
  'rating',
  'userRatingCount',
  'priceLevel',
  'types',
  'primaryType',
  'currentOpeningHours',
  'regularOpeningHours',
  'formattedAddress',
  'nationalPhoneNumber',
  'websiteUri',
  'photos',
  'dineIn',
  'takeout',
  'delivery',
  'reservable',
  'googleMapsUri'
].join(',');

const CACHE_TTL_S = 3600; // 1 hour

export async function handlePlace(placeId, request, env, ctx) {
  if (!placeId || placeId.length > 200 || !/^[A-Za-z0-9_-]+$/.test(placeId)) {
    return jsonError('Invalid place id', 400);
  }

  const cacheKey = `place:${placeId}`;
  const cached = await env.CACHE.get(cacheKey, { type: 'json' });
  if (cached) return jsonOk(cached);

  const data = await fetchPlaceDetails(placeId, FIELD_MASK, env);
  if (data.error) {
    return jsonError("Couldn't load that place right now.", 503);
  }

  ctx.waitUntil(
    env.CACHE.put(cacheKey, JSON.stringify(data), { expirationTtl: CACHE_TTL_S })
  );

  return jsonOk(data);
}
