// Convert Google's Place shape into Bite's Restaurant model.

const TYPE_TO_CATEGORY = {
  italian_restaurant: 'italian',
  pizza_restaurant: 'italian',
  japanese_restaurant: 'japanese',
  sushi_restaurant: 'japanese',
  ramen_restaurant: 'japanese',
  mexican_restaurant: 'mexican',
  taco_restaurant: 'mexican',
  american_restaurant: 'american',
  hamburger_restaurant: 'american',
  steak_house: 'american',
  barbecue_restaurant: 'american',
  diner: 'american',
  mediterranean_restaurant: 'mediterranean',
  greek_restaurant: 'mediterranean',
  middle_eastern_restaurant: 'mediterranean',
  lebanese_restaurant: 'mediterranean',
  french_restaurant: 'mediterranean',
  spanish_restaurant: 'mediterranean',
  thai_restaurant: 'thai',
  vietnamese_restaurant: 'thai',
  indonesian_restaurant: 'thai',
  indian_restaurant: 'indian',
  chinese_restaurant: 'chinese',
  korean_restaurant: 'chinese',
  cafe: 'cafe',
  coffee_shop: 'cafe',
  bakery: 'cafe',
  breakfast_restaurant: 'cafe',
  brunch_restaurant: 'cafe'
};

const PRICE_LEVEL_MAP = {
  PRICE_LEVEL_FREE: 0,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4
};

const TYPE_TO_TAG = {
  bakery: 'bakery',
  cafe: 'cozy',
  coffee_shop: 'cozy',
  bar: 'lively',
  fast_food_restaurant: 'quick',
  fine_dining_restaurant: 'special',
  vegan_restaurant: 'vegan',
  vegetarian_restaurant: 'vegetarian',
  breakfast_restaurant: 'breakfast',
  brunch_restaurant: 'brunch',
  pizza_restaurant: 'pizza',
  ice_cream_shop: 'sweet',
  dessert_shop: 'sweet'
};

// Types that indicate a gas station / convenience store (excluded from main feed)
const GAS_STATION_TYPES = new Set([
  'gas_station', 'fuel_station', 'ev_charging_station'
]);

// Derive useful indicators from Google types
function deriveIndicators(types = []) {
  const indicators = [];
  const typeSet = new Set(types);
  if (typeSet.has('bar') || typeSet.has('night_club') || typeSet.has('wine_bar') || typeSet.has('brewery')) indicators.push('serves-alcohol');
  if (typeSet.has('bar') || typeSet.has('night_club')) indicators.push('21+');
  if (typeSet.has('family_restaurant') || typeSet.has('fast_food_restaurant') || typeSet.has('pizza_restaurant') || typeSet.has('ice_cream_shop')) indicators.push('kid-friendly');
  if (typeSet.has('fine_dining_restaurant')) indicators.push('fine-dining');
  if (typeSet.has('vegan_restaurant')) indicators.push('vegan');
  if (typeSet.has('vegetarian_restaurant')) indicators.push('vegetarian');
  if (typeSet.has('fast_food_restaurant') || typeSet.has('meal_takeaway')) indicators.push('quick-service');
  return indicators;
}

function haversineMiles(lat1, lng1, lat2, lng2) {
  const R = 3958.8; // earth radius in miles
  const toRad = d => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function humanizeCuisine(primaryType) {
  if (!primaryType) return 'Restaurant';
  return primaryType
    .replace(/_restaurant$/, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function mapToCategory(types = []) {
  for (const t of types) {
    if (TYPE_TO_CATEGORY[t]) return TYPE_TO_CATEGORY[t];
  }
  return 'other';
}

function deriveTags(types = []) {
  const tags = [];
  for (const t of types) {
    const tag = TYPE_TO_TAG[t];
    if (tag && !tags.includes(tag)) tags.push(tag);
  }
  return tags.slice(0, 3);
}

function buildDoorDashUrl(name) {
  if (!name) return null;
  return `https://www.doordash.com/search/store/${encodeURIComponent(name)}`;
}

/**
 * Normalize a Google Place into Bite's Restaurant shape.
 * The frontend prepends its own origin to imageUrl when fetching photos.
 */
export function normalizePlace(googlePlace, userLat, userLng) {
  const placeLat = googlePlace.location?.latitude;
  const placeLng = googlePlace.location?.longitude;
  const distance =
    placeLat != null && placeLng != null
      ? Math.round(haversineMiles(userLat, userLng, placeLat, placeLng) * 10) / 10
      : null;

  const photoName = googlePlace.photos?.[0]?.name;
  // Return a relative path; frontend prepends Worker origin.
  const imagePath = photoName
    ? `/api/photo/${encodeURIComponent(photoName)}?maxWidth=800`
    : null;

  const name = googlePlace.displayName?.text || 'Unknown';

  const types = googlePlace.types || [];
  const isGasStation = types.some(t => GAS_STATION_TYPES.has(t));

  return {
    id: googlePlace.id,
    name,
    cuisine: humanizeCuisine(googlePlace.primaryType),
    cuisineCategory: mapToCategory(types),
    priceLevel: PRICE_LEVEL_MAP[googlePlace.priceLevel] ?? 2,
    rating: googlePlace.rating,
    reviewCount: googlePlace.userRatingCount || 0,
    distance,
    travelTimeMin: distance != null ? Math.max(1, Math.round(distance * 3)) : null,
    imagePath,
    imageAlt: `${name} photo`,
    tags: deriveTags(types),
    indicators: deriveIndicators(types),
    isGasStation,
    address: googlePlace.formattedAddress,
    openNow: googlePlace.currentOpeningHours?.openNow ?? null,
    pickup: googlePlace.takeout ?? false,
    delivery: googlePlace.delivery ?? false,
    dineIn: googlePlace.dineIn ?? null,
    doorDashUrl: buildDoorDashUrl(name),
    mapsUrl: googlePlace.googleMapsUri,
    phone: googlePlace.nationalPhoneNumber,
    website: googlePlace.websiteUri,
    lat: placeLat,
    lng: placeLng
  };
}
