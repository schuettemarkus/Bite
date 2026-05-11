// /api/nearby — find restaurants near user lat/lng.

import { fetchNearby } from './places.js';
import { normalizePlace } from './normalize.js';
import { jsonOk, jsonError } from './http.js';

// Pro-tier fields only. Avoid Enterprise (reviews, generativeSummary) in V1.
const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.location',
  'places.rating',
  'places.userRatingCount',
  'places.priceLevel',
  'places.types',
  'places.primaryType',
  'places.currentOpeningHours.openNow',
  'places.currentOpeningHours.weekdayDescriptions',
  'places.currentOpeningHours.periods',
  'places.formattedAddress',
  'places.nationalPhoneNumber',
  'places.websiteUri',
  'places.photos',
  'places.dineIn',
  'places.takeout',
  'places.delivery',
  'places.googleMapsUri'
].join(',');

const INCLUDED_TYPES = [
  'restaurant',
  'cafe',
  'bakery',
  'meal_takeaway',
  'breakfast_restaurant',
  'brunch_restaurant',
  'coffee_shop'
];

const MIN_RATING = 4.0;
const DEFAULT_RADIUS_M = 8000; // 8km ~ 5 mi
const MAX_RADIUS_M = 50000; // 50km ~ 31 mi (Google Places API max)
const MAX_RESULTS = 20;
const CACHE_TTL_S = 3600; // 1 hour

export async function handleNearby(request, env, ctx) {
  const url = new URL(request.url);
  const lat = parseFloat(url.searchParams.get('lat'));
  const lng = parseFloat(url.searchParams.get('lng'));
  const requestedRadius = parseInt(url.searchParams.get('radius'), 10) || DEFAULT_RADIUS_M;
  const radius = Math.min(Math.max(requestedRadius, 500), MAX_RADIUS_M);

  if (!isFinite(lat) || !isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return jsonError('Invalid coordinates', 400);
  }

  // Cache key uses rounded coords (~110m grid) so neighbors share cache hits.
  // Privacy: never log raw user coords; KV key resolution is intentionally coarse.
  const gridLat = lat.toFixed(3);
  const gridLng = lng.toFixed(3);
  const cacheKey = `nearby:${gridLat}:${gridLng}:${radius}`;

  const cached = await env.CACHE.get(cacheKey, { type: 'json' });
  if (cached?.places) {
    // Re-compute distance from actual user coords on every hit.
    const restaurants = cached.places
      .map(p => normalizePlace(p, lat, lng))
      .sort((a, b) => (a.distance ?? Infinity) - (b.distance ?? Infinity));
    return jsonOk({ restaurants, cached: true });
  }

  // Cache miss — call Google.
  const data = await fetchNearby(
    {
      lat, lng, radius,
      includedTypes: INCLUDED_TYPES,
      maxResultCount: MAX_RESULTS,
      fieldMask: FIELD_MASK
    },
    env
  );

  if (data.error) {
    console.error('Google Places API error:', JSON.stringify(data.error).slice(0, 200));
    if (data.status === 429) {
      return jsonError("Bite's been busy. Try again in a moment.", 503);
    }
    if (data.error?.status === 'INVALID_ARGUMENT') {
      return jsonError("Search area too large. Try a smaller distance.", 400);
    }
    return jsonError("Bite is having trouble reaching the kitchen.", 503);
  }

  const places = data.places || [];

  // Types that should never appear — even if Google returns them as dual-typed
  const EXCLUDED_PRIMARY = new Set([
    'gas_station', 'fuel_station', 'ev_charging_station',
    'grocery_store', 'supermarket', 'convenience_store',
    'drugstore', 'pharmacy', 'hospital', 'dentist', 'doctor',
    'car_wash', 'car_repair', 'car_dealer', 'parking',
    'lodging', 'hotel', 'motel', 'campground',
    'shopping_mall', 'department_store', 'clothing_store',
    'gym', 'stadium', 'movie_theater', 'amusement_park',
    'church', 'school', 'university', 'library',
    'bank', 'atm', 'post_office', 'laundry',
  ]);

  // Enforce 4-star minimum + exclude non-restaurant types BEFORE caching.
  const filtered = places.filter(p => {
    if (typeof p.rating !== 'number' || p.rating < MIN_RATING) return false;
    // Exclude if primary type is non-restaurant
    if (p.primaryType && EXCLUDED_PRIMARY.has(p.primaryType)) return false;
    // Exclude if any top-level type is in the exclusion list and no restaurant type present
    const types = p.types || [];
    const hasRestaurantType = types.some(t =>
      t.includes('restaurant') || t === 'cafe' || t === 'bakery' ||
      t === 'coffee_shop' || t === 'meal_takeaway' || t === 'food'
    );
    const hasExcludedType = types.some(t => EXCLUDED_PRIMARY.has(t));
    if (hasExcludedType && !hasRestaurantType) return false;
    return true;
  });

  // Cache the raw filtered list (without computed distance — that varies per user).
  ctx.waitUntil(
    env.CACHE.put(cacheKey, JSON.stringify({ places: filtered }), {
      expirationTtl: CACHE_TTL_S
    })
  );

  const restaurants = filtered
    .map(p => normalizePlace(p, lat, lng))
    .sort((a, b) => (a.distance ?? Infinity) - (b.distance ?? Infinity));

  return jsonOk({ restaurants, cached: false });
}
