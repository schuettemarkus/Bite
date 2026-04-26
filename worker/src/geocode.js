// /api/geocode — ZIP/address → lat/lng (for permission-denied fallback)
// /api/reverse-geocode — lat/lng → neighborhood name (for Home location chip)

import { fetchGeocode, fetchReverseGeocode } from './places.js';
import { jsonOk, jsonError } from './http.js';

const FORWARD_TTL_S = 30 * 24 * 3600; // 30 days — postal codes don't move
const REVERSE_TTL_S = 7 * 24 * 3600;  // 7 days

// ─── Forward: ZIP / address → coordinates ──────────────────────────────

export async function handleGeocode(request, env, ctx) {
  const url = new URL(request.url);
  const raw = (url.searchParams.get('zip') || url.searchParams.get('address') || '').trim();

  // Loose validation — accepts US ZIPs, UK postcodes, "City, ST" etc. Caps length.
  if (!raw || raw.length > 100 || !/^[A-Za-z0-9 ,.-]{2,100}$/.test(raw)) {
    return jsonError('Invalid postal code or address', 400);
  }

  const cacheKey = `geocode:${raw.toLowerCase()}`;
  const cached = await env.CACHE.get(cacheKey, { type: 'json' });
  if (cached) return jsonOk(cached);

  const data = await fetchGeocode(raw, env);
  if (data.error || data.status !== 'OK' || !data.results?.length) {
    return jsonError("Couldn't find that location.", 404);
  }

  const top = data.results[0];
  const normalized = {
    lat: top.geometry.location.lat,
    lng: top.geometry.location.lng,
    formatted: top.formatted_address,
    neighborhood: pickNeighborhood(top.address_components)
  };

  ctx.waitUntil(
    env.CACHE.put(cacheKey, JSON.stringify(normalized), { expirationTtl: FORWARD_TTL_S })
  );

  return jsonOk(normalized);
}

// ─── Reverse: coordinates → neighborhood / city ────────────────────────

export async function handleReverseGeocode(request, env, ctx) {
  const url = new URL(request.url);
  const lat = parseFloat(url.searchParams.get('lat'));
  const lng = parseFloat(url.searchParams.get('lng'));

  if (!isFinite(lat) || !isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return jsonError('Invalid coordinates', 400);
  }

  // Round to ~1km grid for cache reuse and to avoid storing precise user coords.
  const gridLat = lat.toFixed(2);
  const gridLng = lng.toFixed(2);
  const cacheKey = `revgeo:${gridLat}:${gridLng}`;

  const cached = await env.CACHE.get(cacheKey, { type: 'json' });
  if (cached) return jsonOk(cached);

  const data = await fetchReverseGeocode(parseFloat(gridLat), parseFloat(gridLng), env);
  if (data.error || data.status !== 'OK' || !data.results?.length) {
    // Soft failure — return null so the chip just shows nothing.
    return jsonOk({ neighborhood: null, city: null });
  }

  const components = data.results[0].address_components || [];
  const result = {
    neighborhood: pickNeighborhood(components),
    city: pickCity(components),
    region: pickRegion(components)
  };

  ctx.waitUntil(
    env.CACHE.put(cacheKey, JSON.stringify(result), { expirationTtl: REVERSE_TTL_S })
  );

  return jsonOk(result);
}

// ─── Address-component helpers ─────────────────────────────────────────

function pickNeighborhood(components = []) {
  const find = type => components.find(c => c.types.includes(type))?.long_name;
  return find('neighborhood') || find('sublocality') || find('sublocality_level_1') || null;
}

function pickCity(components = []) {
  const find = type => components.find(c => c.types.includes(type))?.long_name;
  return find('locality') || find('postal_town') || find('administrative_area_level_2') || null;
}

function pickRegion(components = []) {
  const region = components.find(c => c.types.includes('administrative_area_level_1'));
  return region?.short_name || region?.long_name || null;
}
