// Google Places API (New) + Geocoding API client.
// All calls go through here so error handling and headers stay consistent.

const PLACES_BASE = 'https://places.googleapis.com/v1';
const GEOCODE_BASE = 'https://maps.googleapis.com/maps/api/geocode/json';

export async function fetchNearby({ lat, lng, radius, includedTypes, maxResultCount, fieldMask }, env) {
  const body = {
    includedTypes,
    maxResultCount,
    rankPreference: 'DISTANCE',
    locationRestriction: {
      circle: {
        center: { latitude: lat, longitude: lng },
        radius
      }
    }
  };

  const res = await fetch(`${PLACES_BASE}/places:searchNearby`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': env.GOOGLE_PLACES_KEY,
      'X-Goog-FieldMask': fieldMask
    },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    const errBody = await res.text().catch(() => '');
    console.error(`Nearby Search error ${res.status}: ${errBody.slice(0, 500)}`);
    return { error: true, status: res.status };
  }

  return res.json();
}

export async function fetchPlaceDetails(placeId, fieldMask, env) {
  const res = await fetch(`${PLACES_BASE}/places/${encodeURIComponent(placeId)}`, {
    headers: {
      'X-Goog-Api-Key': env.GOOGLE_PLACES_KEY,
      'X-Goog-FieldMask': fieldMask
    }
  });

  if (!res.ok) {
    const errBody = await res.text().catch(() => '');
    console.error(`Place Details error ${res.status}: ${errBody.slice(0, 500)}`);
    return { error: true, status: res.status };
  }

  return res.json();
}

export async function fetchPhotoUri(photoName, maxWidth, env) {
  // skipHttpRedirect=true returns JSON with a signed photoUri instead of a 302.
  // Signed URLs are typically valid ~1 hour.
  const url = `${PLACES_BASE}/${photoName}/media?maxWidthPx=${maxWidth}` +
    `&key=${env.GOOGLE_PLACES_KEY}&skipHttpRedirect=true`;

  const res = await fetch(url);
  if (!res.ok) {
    console.error(`Photo error ${res.status}`);
    return null;
  }
  const data = await res.json();
  return data.photoUri || null;
}

export async function fetchGeocode(address, env) {
  const url = new URL(GEOCODE_BASE);
  url.searchParams.set('address', address);
  url.searchParams.set('key', env.GOOGLE_PLACES_KEY);

  const res = await fetch(url.toString());
  if (!res.ok) return { error: true };
  return res.json();
}

export async function fetchReverseGeocode(lat, lng, env) {
  const url = new URL(GEOCODE_BASE);
  url.searchParams.set('latlng', `${lat},${lng}`);
  url.searchParams.set('result_type', 'neighborhood|sublocality|locality');
  url.searchParams.set('key', env.GOOGLE_PLACES_KEY);

  const res = await fetch(url.toString());
  if (!res.ok) return { error: true };
  return res.json();
}
