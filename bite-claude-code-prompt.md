# Bite — Claude Code Implementation Prompt

> **Tagline:** Decide before the hunger does.
> **Mission:** Be the calmest, fastest restaurant decision tool ever built.
> **North-star metric:** Time from app open to "I'm going there." Target: under 8 seconds.

---

## 0. Prerequisites (set up before building)

These three accounts/keys are needed before Claude Code can complete V1:

1. **Google Cloud project with Places API (New) enabled**
   - Create a project at console.cloud.google.com
   - Enable: *Places API (New)*, *Geocoding API*
   - Create an API key, restrict to the Worker's domain only
   - Note: Places API is now Legacy and locked for new projects — use Places API (New) which is the current version
2. **Cloudflare account** (free tier is fine for V1)
   - Install `wrangler` CLI: `npm i -g wrangler`
   - Workers KV namespace for the cache
3. **Domain or workers.dev subdomain** for the deployed Worker

Place the Google API key into the Worker as a secret:
```
wrangler secret put GOOGLE_PLACES_KEY
```

Never commit the key. Never expose it client-side.

---

## 1. Vision

Every day, ~150M Americans face the question *"what should we eat?"* — a high-frequency, low-stakes decision that nonetheless creates real friction, especially for couples, families, and the chronically indecisive. Existing apps (Yelp, Google Maps, DoorDash) optimize for **browsing**. Bite optimizes for **deciding**.

The product opens in under 1 second, gives a great answer in under 5, and gets out of the way. It feels like a deep breath, not a doomscroll.

**Anti-patterns we explicitly reject:**
- No streaks. No leaderboards. No badges.
- No red dots. Anywhere. Ever.
- No push notifications by default.
- No infinite scroll.
- No sponsored placements above organic ones.
- No login wall before first use.

---

## 2. Brand & Tone

| Attribute | Value |
|---|---|
| Name | **Bite** |
| Tagline | Decide before the hunger does. |
| Voice | Warm, brief, never cute. A friend who knows the city. |
| Vibe | A linen napkin, not a neon sign. |

---

## 3. The Calm Stack — Core Design Principles

1. **One decision per screen.** Never two competing CTAs.
2. **Default to the answer.** Show the recommendation first, options second.
3. **Generous touch targets.** 56pt minimum. Thumb-zone biased.
4. **Slow on purpose.** 280–400ms spring animations. Never punchy.
5. **Quiet color.** Warm neutrals. Sage and terracotta accents. No saturation spikes.
6. **Optional everything.** Onboarding skippable. Filters collapsible. Login deferred.
7. **Privacy is calming.** Local-first by default. No tracking pixels. No data sold.

---

## 4. The 10 Features

### 4.1 Mood-First Home
Three large cards stacked vertically:
- **Familiar** (sage tint) — "Places you'll love."
- **New** (terracotta tint) — "Worth the discovery."
- **Surprise Me** (cream) — "We'll just decide."

Below: optional horizontal-scroll mood chip row — *Quick · Cozy · Celebrating · Nourishing · Comfort*. No search bar by default; search is one tap behind a small icon.

### 4.2 The Big Button (Auto-Decide)
A single, tactile button at the bottom of Home: **"Decide for me."** One tap consults Taste DNA, current time, weather, location, busy times, and recent history, then surfaces a single restaurant card with action buttons. The fastest path from hunger to answer in any app.

### 4.3 Swipe Stack
Tinder-style discovery, hard-capped at **7 cards per session** to prevent fatigue. Spring physics, soft haptics.
- **Right** → match (card flips to action sheet)
- **Left** → pass (next card scales in)
- **Up** → save for later (toast: "Saved")

### 4.4 Taste DNA
A living, visual profile that updates passively from every interaction. Visualized as a soft radar chart, not a list. Tracks: cuisines, price tolerance, spice tolerance, dietary needs, time-of-day patterns, adventurousness. Cross-device synced via account (V2+).

### 4.5 Group Sync
Two or more people open the app and join a session via 4-character code. Each swipes independently. The app surfaces mutual matches in real time. Sessions auto-expire after 30 minutes.

### 4.6 Context Engine
Recommendations factor in: time of day (breakfast vs late-night), weather (rainy = comfort food bias), day of week, distance, current open status, busy times, recent visits. All transparent — show **"Why this?"** chip on tap.

### 4.7 Inline Action Buttons
On match, action options live on the card itself:
- 📍 **Pickup** — opens Apple/Google Maps with directions
- 🛵 **Delivery** — DoorDash deep link
- ☎️ **Call** — tel: link

No detail page. No extra navigation.

### 4.8 Variety Memory
Won't suggest a restaurant visited in the past 14 days unless user taps "Again." User-controlled slider: **Adventurous ↔ Reliable** (default 50/50). Surfaces a soft "you've been on a streak — want something new?" suggestion when the user has gone to the same place 3+ times.

### 4.9 Quiet Save & Share
Long-press any restaurant card to save. Tap share to send a match to a partner with a single tap (deep link opens Bite for them). Saved list lives in profile, no folders, no organization required.

### 4.10 Calm Mode UI
The visual system *is* the feature: warm cream background, generous whitespace, soft serif headers, big readable body text, subtle haptics, optional ambient sound (soft "thunk" on match — off by default), and zero notification badges anywhere in the system.

---

## 5. Tech Stack

### V1 — Web PWA + Edge Proxy (this prompt's scope)
- **Frontend:** Single-file `index.html` with embedded CSS + JS, Tailwind via CDN
- **Backend:** Cloudflare Worker (~150 lines) proxying Google Places API
- **Data:** Live from **Google Places API (New)** — Nearby Search, Place Details, Place Photo
- **Location:** Browser Geolocation API with ZIP code fallback
- **Storage:** LocalStorage for Taste DNA, saved restaurants, recent visits, cached location
- **Caching:** Workers KV (server) + Service Worker (client) — see §6.9.5
- **Group Sync MVP:** BroadcastChannel API (single-device multi-tab) for V1; real cross-device in V2

### V2 — React Native + Backend
- Expo, cross-platform
- Supabase backend (auth, taste DNA sync, real Group Sync via Realtime channels)
- Same Places API integration, now with shared cross-user tile cache
- Routes API for accurate travel times
- DoorDash Drive deep linking, Apple/Google Maps native handoff
- Shared element transitions
- iCloud Keychain / Google credential sync

### V3 — Ambient computing
- Apple Watch complication: one-tap "Decide for me" from the wrist
- iMessage extension for Group Sync
- On-device ML model for taste prediction (CoreML / TFLite)

---

## 6. V1 Build Spec

### 6.1 File Structure
```
bite/
├── web/
│   ├── index.html          # entire frontend app, single file
│   ├── manifest.json       # PWA manifest
│   ├── service-worker.js   # offline cache + API response cache
│   └── icons/              # 192, 512, maskable
├── worker/
│   ├── src/index.js        # Cloudflare Worker proxy
│   ├── wrangler.toml       # Worker config
│   └── README.md           # deploy instructions
└── README.md               # build/run notes
```

The frontend is still a single-file PWA. The Worker is a tiny proxy (~150 lines) that hides the Google API key, applies the `>=4.0 rating` filter, normalizes responses to our data model, and caches aggressively.

### 6.2 Design Tokens

```css
:root {
  /* Surface */
  --bg: #FBF7F0;             /* warm cream */
  --surface: #FFFFFF;
  --surface-2: #F4EFE6;
  --sand: #E8E2D5;           /* dividers */

  /* Ink */
  --ink: #2D2A26;            /* warm black */
  --ink-muted: #6B6660;
  --ink-soft: #9B958A;

  /* Accents */
  --sage: #6B8E5A;           /* match / go / yes */
  --sage-soft: #DCE6D4;
  --terracotta: #D97757;     /* primary action */
  --terracotta-soft: #F4D9CC;
  --rose: #C97A6A;           /* secondary */

  /* Effects */
  --shadow-sm: 0 2px 12px rgba(45, 42, 38, 0.04);
  --shadow-md: 0 4px 24px rgba(45, 42, 38, 0.06);
  --shadow-lg: 0 16px 48px rgba(45, 42, 38, 0.10);

  /* Radius */
  --radius-sm: 12px;
  --radius-md: 20px;
  --radius-lg: 28px;
  --radius-xl: 36px;

  /* Spacing (8pt grid) */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 16px;
  --space-4: 24px;
  --space-5: 32px;
  --space-6: 48px;
  --space-7: 64px;

  /* Motion */
  --duration-fast: 180ms;
  --duration-base: 320ms;
  --duration-slow: 480ms;
  --ease-out: cubic-bezier(0.32, 0.72, 0.24, 1.08);
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);
}
```

### 6.3 Typography

| Role | Font | Size | Weight |
|---|---|---|---|
| Display | Tiempos Headline / Source Serif Pro / Georgia | 32pt | 500 |
| H1 | (serif) | 28pt | 500 |
| H2 | (serif) | 22pt | 500 |
| Body | Inter / system-ui | 17pt | 400 |
| Body small | Inter | 15pt | 400 |
| Caption | Inter | 13pt | 500 |

Line height 1.4 for body, 1.2 for display. Letter-spacing -0.01em on serif headers.

### 6.4 Routes (single-page hash-based)

| Route | View |
|---|---|
| `#home` | Mood cards + Big Button |
| `#swipe` | Swipe stack |
| `#match/{id}` | Match card with inline actions |
| `#group` | Group session join/create |
| `#group/{code}` | Active group session |
| `#dna` | Taste DNA profile |
| `#saved` | Saved restaurants |
| `#settings` | Preferences |
| `#why/{id}` | Reasoning explanation modal |

### 6.5 Data Models

**Restaurant**
```js
{
  id: 'r_001',
  name: 'Tartine Bakery',
  cuisine: 'Bakery / Café',
  cuisineCategory: 'bakery',
  priceLevel: 2,             // 1–4
  rating: 4.6,               // must be >= 4.0 to surface
  reviewCount: 3421,
  distance: 0.8,             // miles from user
  travelTimeMin: 12,
  imageUrl: 'https://...',
  imageAlt: 'Pastries on a wooden board',
  tags: ['cozy', 'casual', 'breakfast'],
  hours: { open: '07:00', close: '19:00' },
  openNow: true,
  busyLevel: 'moderate',     // quiet | moderate | busy
  pickup: true,
  delivery: true,
  doorDashUrl: 'https://...',
  mapsUrl: 'maps://?q=...',
  phone: '+14155551234',
  lat: 37.7615,
  lng: -122.4239,
  vibe: ['warm-light', 'wood', 'plants']  // for "why this?"
}
```

**Taste DNA (LocalStorage key: `bite.dna`)**
```js
{
  cuisines: {
    italian: 0.8, japanese: 0.6, mexican: 0.4,
    american: 0.7, mediterranean: 0.5, thai: 0.3,
    indian: 0.5, chinese: 0.6, other: 0.4
  },
  priceRange: [1, 3],          // min, max
  spiceTolerance: 0.7,         // 0–1
  diet: ['vegetarian'],        // [] | ['vegan'] | ['gluten-free'] | etc.
  adventurousness: 0.5,        // 0=reliable, 1=adventurous
  maxDistance: 3.0,            // miles
  recentVisits: [
    { id: 'r_001', timestamp: 1714000000000 }
  ],
  saved: ['r_007', 'r_012'],
  matchHistory: [
    { id: 'r_003', timestamp: ..., action: 'pickup' }
  ],
  lastSession: 1714000000000
}
```

**Group Session**
```js
{
  code: 'BLOM',                // 4-char, no I/O/0/1
  createdAt: timestamp,
  expiresAt: timestamp + 30*60*1000,
  members: [
    { id: 'u_local', name: 'You', joined: timestamp },
    { id: 'u_xyz', name: 'Maya', joined: timestamp }
  ],
  swipes: {
    'u_local': { 'r_001': 'right', 'r_002': 'left' },
    'u_xyz':   { 'r_001': 'right', 'r_002': 'right' }
  },
  matches: ['r_001']           // computed: where all members swiped right
}
```

### 6.6 Screen-by-Screen Spec

#### Home (`#home`)
- Top bar: small "Bite" wordmark center (serif, 18pt), avatar circle right (links to `#dna`)
- **Location chip**: just below top bar, centered, 32pt tall, soft sand background, 16pt radius. Shows neighborhood + city ("Mission, SF") with a tiny pin icon. Tap to refresh or change. If location is loading, shows shimmering "Finding you…" skeleton chip.
- Hero text 32pt serif, top padding 32pt: **"What feels right?"** (rotates: "What sounds good?", "Hungry?", "Let's eat.")
- Three cards, full-width minus 24pt gutters, 120pt tall, 24pt vertical gap:
  - Familiar — sage-soft background, sage left border 4pt
  - New — terracotta-soft background, terracotta left border 4pt
  - Surprise Me — cream surface-2 background
- Each card: title (22pt serif) + subtitle (15pt muted) + tiny right-chevron
- Mood chip row below, 32pt tall chips, horizontal scroll, no scrollbar
- Bottom-fixed: **"Decide for me"** button — 64pt tall, full-width minus 24pt, terracotta, white text, 17pt semibold, 28pt radius, soft shadow. **Disabled (50% opacity) until location is resolved.**

**First-open state (no location yet):** Replace the three mood cards with a single full-width primer card:
- Soft pin icon (sage) centered, 48pt
- Title (22pt serif): "Find good food nearby"
- Body (15pt muted): "Bite uses your location to recommend restaurants. We don't store it."
- Two stacked buttons: **Use my location** (terracotta, 56pt) and **Enter a ZIP code** (text link, 17pt sage)
- The Big Button is hidden in this state — there's literally one decision to make.

#### Swipe (`#swipe`)
- Top bar: back arrow left, "1 of 7" counter center (13pt muted), close X right
- Card stack, 90% screen width, 70% screen height, centered
- Top card layout:
  - Hero photo 60% of card height, top corners rounded
  - Padding 24pt below photo
  - Name 24pt serif
  - Cuisine · $$ · 0.8 mi (15pt muted, dot-separated)
  - Rating: "4.6 · 3.4k reviews" — no star icons (calm)
  - 3 tag chips, 28pt tall
- Behind top card, next card peeks 8pt below, scaled 0.96
- Swipe right: card animates off right with 18° rotation, then flips to action sheet
- Swipe left: card animates off left with -18° rotation, scale 0.9
- Swipe up: card lifts 60pt with bounce, toast "Saved", returns
- Bottom: subtle 7-dot pagination

#### Match (`#match/{id}`)
- Card flipped from swipe view (3D rotateY animation, 600ms ease-spring)
- Hero photo 35% of card
- Name + cuisine · $$ · distance
- Three stacked action buttons, 56pt tall, 16pt gap:
  - **📍 Pickup** — sage-soft background, sage text → opens Maps
  - **🛵 Delivery** — terracotta-soft background, terracotta text → DoorDash deep link
  - **☎️ Call** — surface-2 background, ink text → tel:
- "Why this?" link below (15pt sage, underlined) → expands inline to show 2–3 reason chips
- Footer: "Not it?" link (15pt muted) → returns to swipe with refreshed stack

#### Group (`#group`)
Two paths, each a card:
- **Create session** — generates 4-char code, big share button
- **Join session** — 4-char code input (auto-uppercase, no I/O/0/1)

Active session (`#group/{code}`):
- Top: code displayed large (28pt mono), members chips below
- "🟢 Maya is swiping" status
- Same swipe stack as solo, but mutual matches trigger modal: **"You both swiped right on Tartine."** with same inline actions

#### Taste DNA (`#dna`)
- Top: avatar + name (or "Set up profile" if anonymous)
- Radar chart, 280pt square, 6 axes (Italian, Asian, Mexican, American, Mediterranean, Other)
  - Chart: SVG, sage stroke, sage-soft fill at 40% opacity, no grid labels (clean)
- Below: "You tend to like…" 3-sentence summary in body text, dynamically generated from DNA
- Sliders (3): Adventurousness, Price Range (dual-thumb), Distance Tolerance
- Diet toggles (chips, multi-select): Vegetarian, Vegan, Gluten-free, Halal, Kosher, Pescatarian, Dairy-free
- Footer: "Synced across your devices" pill (V2+) or "Stored on this device" (V1)

#### Saved (`#saved`)
- Simple vertical list of cards, 88pt tall, photo left 88x88 + name/cuisine right
- Tap → match view
- Long-press → remove
- Empty state: "Things you save show up here." + soft illustration

#### Settings (`#settings`)
- Account (V2+)
- Notifications: all off by default, single toggle "Quiet matches only"
- Sound: ambient haptic toggle + match sound toggle (both default off)
- Privacy: "Export my data" / "Delete my data" (local in V1)
- About / Version

### 6.7 Animation & Interaction Specs

| Interaction | Animation |
|---|---|
| Card swipe | Spring: stiffness 280, damping 24 |
| Match flip | 3D rotateY 180°, 600ms ease-spring |
| Big Button press | Scale 0.96, 150ms ease-out |
| Mood card tap | Subtle pulse (scale 1→1.02→1), 200ms |
| Page transition | Cross-fade + 8pt slide, 320ms |
| Toast appear | Slide-up 16pt + fade, 240ms; auto-dismiss 1800ms |
| Modal appear | Backdrop fade + content slide-up 24pt, 320ms |
| Skeleton shimmer | 1500ms loop, gentle (no chase) |

### 6.8 Haptics (Web Vibration API where supported)

| Event | Pattern |
|---|---|
| Swipe right | `[20]` |
| Swipe left | `[10]` |
| Swipe up (save) | `[15]` |
| Match | `[20, 60, 30]` |
| Big Button tap | `[25]` |
| Long-press save | `[12]` |

### 6.9 Live Data Architecture

**No mock data.** V1 uses real restaurants from the moment of first launch.

#### 6.9.1 Geolocation Flow (calm, not pushy)

1. **First-open priming.** Before triggering the browser's permission dialog, show a calm primer card on Home: small location pin icon, soft text: *"Bite needs to know where you are to find good food nearby."* Two buttons: **Use my location** (terracotta, primary) and **Enter a ZIP code** (text link, secondary).
2. **On tap of "Use my location"**, call `navigator.geolocation.getCurrentPosition()` with `{ enableHighAccuracy: false, maximumAge: 600000, timeout: 8000 }`. Lower accuracy = faster fix and easier on battery; 10-min cache means repeat opens don't re-prompt.
3. **Cache the position** in LocalStorage as `bite.location = { lat, lng, accuracy, timestamp, source: 'gps' | 'manual' }`. Reuse for 30 minutes before refreshing silently in background.
4. **If denied**, fall back to ZIP code input. Use Google Geocoding API (via Worker) to convert ZIP → lat/lng. Cache result the same way with `source: 'manual'`.
5. **Refresh control.** A small location chip at the top of Home shows the current neighborhood (reverse geocoded, e.g., "Mission, SF"). Tap to refresh or change manually.
6. **Never ask twice in one session.** Respect denial — if denied, never re-prompt; just always show the ZIP input.

#### 6.9.2 Data Source: Google Places API (New)

Use the **Nearby Search (New)** endpoint as the primary discovery call:

```
POST https://places.googleapis.com/v1/places:searchNearby
```

**Request shape (sent by our Worker):**
```json
{
  "includedTypes": ["restaurant", "cafe", "bakery", "meal_takeaway"],
  "maxResultCount": 20,
  "rankPreference": "DISTANCE",
  "locationRestriction": {
    "circle": {
      "center": { "latitude": 37.7749, "longitude": -122.4194 },
      "radius": 5000
    }
  }
}
```

**FieldMask header (CRITICAL — controls cost):**
```
X-Goog-FieldMask: places.id,places.displayName,places.location,
  places.rating,places.userRatingCount,places.priceLevel,
  places.types,places.primaryType,places.currentOpeningHours.openNow,
  places.formattedAddress,places.nationalPhoneNumber,places.websiteUri,
  places.photos,places.dineIn,places.takeout,places.delivery,
  places.googleMapsUri
```

These fields stay within the Pro SKU tier — avoid Enterprise fields (e.g., `editorialSummary`, `reviews`, `generativeSummary`) in V1 to keep costs predictable. AI-powered summaries are a V2+ feature once we know unit economics.

#### 6.9.3 Cloudflare Worker Proxy (`worker/src/index.js`)

The Worker has three responsibilities:

1. **Hide the Google API key.** Stored as a Worker secret (`wrangler secret put GOOGLE_PLACES_KEY`).
2. **Filter and normalize.** Drops anything below 4.0 stars, maps Google's response shape to our internal `Restaurant` model, computes distance via Haversine.
3. **Cache aggressively.** Uses Workers KV with a key of rounded location grid (`lat:0.005, lng:0.005` ≈ 500m cells) and 1-hour TTL. Repeat queries from the same neighborhood are served from cache, slashing API spend.

**Endpoints the Worker exposes:**

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/nearby?lat={n}&lng={n}&radius={m}` | Returns normalized restaurant array |
| `GET` | `/api/place/{id}` | Returns full Place Details (lazy-loaded for match view) |
| `GET` | `/api/photo/{ref}?maxWidth=800` | Proxies Place Photo (so frontend never sees API key) |
| `GET` | `/api/geocode?zip={code}` | Converts ZIP → lat/lng for fallback flow |

**CORS:** Allow only the production frontend origin and `localhost:*` for dev.

**Rate limiting:** Use Cloudflare's per-IP rate limit at 60 req/min — generous enough for normal use, blocks abuse.

#### 6.9.4 Data Normalization

The Worker converts Google's response into our `Restaurant` shape:

```js
function normalizePlace(googlePlace, userLat, userLng) {
  const distMiles = haversine(
    userLat, userLng,
    googlePlace.location.latitude, googlePlace.location.longitude
  );
  return {
    id: googlePlace.id,
    name: googlePlace.displayName.text,
    cuisine: humanizeCuisine(googlePlace.primaryType),
    cuisineCategory: mapToCategory(googlePlace.types),
    priceLevel: convertPriceLevel(googlePlace.priceLevel),  // PRICE_LEVEL_MODERATE → 2
    rating: googlePlace.rating,
    reviewCount: googlePlace.userRatingCount,
    distance: round(distMiles, 1),
    travelTimeMin: Math.round(distMiles * 3),  // rough: 20mph city avg
    imageUrl: googlePlace.photos?.[0]
      ? `${WORKER_ORIGIN}/api/photo/${encodeURIComponent(googlePlace.photos[0].name)}?maxWidth=800`
      : FALLBACK_IMAGE,
    imageAlt: `${googlePlace.displayName.text} exterior`,
    tags: deriveTags(googlePlace.types),
    openNow: googlePlace.currentOpeningHours?.openNow ?? false,
    pickup: googlePlace.takeout ?? false,
    delivery: googlePlace.delivery ?? false,
    doorDashUrl: `https://www.doordash.com/search/?query=${encodeURIComponent(googlePlace.displayName.text)}`,
    mapsUrl: googlePlace.googleMapsUri,
    phone: googlePlace.nationalPhoneNumber,
    lat: googlePlace.location.latitude,
    lng: googlePlace.location.longitude,
  };
}
```

**Cuisine category mapping** (used by Taste DNA): a small lookup table converts Google's verbose `types` array (e.g., `["italian_restaurant", "restaurant", "food", "point_of_interest"]`) into our 9-bucket DNA model (italian, japanese, mexican, american, mediterranean, thai, indian, chinese, other).

**Price level mapping:** Google returns string enums (`PRICE_LEVEL_FREE`, `_INEXPENSIVE`, `_MODERATE`, `_EXPENSIVE`, `_VERY_EXPENSIVE`); map to our 1–4 integer scale.

#### 6.9.5 Caching Strategy (cost defense)

Three layers:

1. **Worker KV cache** (server-side). Key = `nearby:{round(lat, 3)}:{round(lng, 3)}:{radius}`. TTL 1 hour. ~110m grid resolution — plenty for "nearby restaurants" use case.
2. **Service Worker cache** (client-side). Cache `/api/photo/*` responses for 7 days (photos rarely change). Cache `/api/nearby/*` for 5 minutes for instant back-navigation.
3. **In-memory cache** (per session). The current session's restaurant pool stays in JS memory until next location refresh — swiping back never re-fetches.

#### 6.9.6 Distance Filtering

The frontend, not the Worker, applies the user's `dna.maxDistance` filter. The Worker always fetches a fixed 5km radius (≈3 miles) to maximize cache hits across users with different distance preferences. If the user has set maxDistance > 3 miles, the frontend issues a second wider query (radius 8km) and merges results.

#### 6.9.7 Cost Sanity Check

With aggressive caching, expected per-user-day API spend:
- 2–4 location refreshes/day × 1 Nearby Search call (when cache miss)
- ~2 Place Details calls (only on match, lazy-loaded)
- ~5 Photo proxies (lazy-loaded as cards surface)
- Most days, cached neighborhood = zero Nearby calls

With Google's free monthly tier (10K Essentials, 5K Pro events) and our caching, a single dev/test user generates ~$0/mo. A consumer rollout to thousands needs the V2 backend with proper tile caching across users — but that's V2's problem.

#### 6.9.8 Loading & Error States

| State | UX |
|---|---|
| Fetching location | Soft skeleton card with "Finding good places near you…" — never spinners |
| Fetching restaurants | Same skeleton, swap text to "Almost there…" after 1.5s |
| No results within distance | "No 4-star spots within {n} miles. Try widening your search?" + slider link |
| Network failure | "Bite can't reach the kitchen. Try again?" + retry button |
| Permission denied | Inline ZIP code input, no scolding copy |
| Outside service area (no results in any radius) | "Bite works best in cities right now. We're working on more places." |

### 6.10 The Recommendation Algorithm (V1)

```
function recommend(mode, dna, time, weather, candidates):
  pool = candidates
        .filter(rating >= 4.0)              // enforced by Worker, double-check here
        .filter(openNow)
        .filter(distance <= dna.maxDistance)
        .filter(priceLevel in dna.priceRange)
        .filter(meets dna.diet requirements)
        .filter(not in last 14 days of dna.recentVisits)

  for each restaurant:
    score = 0
    score += dna.cuisines[r.cuisineCategory] * 30
    score += (1 - r.distance / dna.maxDistance) * 25      // distance is heavily weighted
    score += (1 - abs(r.priceLevel - avg(dna.priceRange))) * 15
    score += contextBonus(time, weather, r.tags) * 15
    score += dna.adventurousness * noveltyScore(r, dna) * 15

  if mode == 'familiar':
    weight cuisines user already likes (>0.6) higher
  if mode == 'new':
    weight cuisines user has tried <3 times higher
  if mode == 'surprise':
    add ±15% random jitter to all scores

  return top result(s) by score
```

**Cold-start (no DNA yet):** Distance becomes the dominant signal (40% weight), supplemented by rating (20%) and price diversity (20%). After ~10 swipes, DNA takes over.

---

## 7. Accessibility (non-negotiable)

- WCAG 2.2 AA contrast minimums (test all color pairs)
- All interactive elements have visible focus states (2pt sage outline, 2pt offset)
- Dynamic type support: respect user font-size preference
- VoiceOver/TalkBack labels on every actionable element
- Swipe gestures have button alternatives (👍 👎 ⭐ row beneath card stack)
- Reduced motion: respect `prefers-reduced-motion` — disable card flips and spring bounces, replace with cross-fades
- Color is never the only signal: icons + text accompany sage/terracotta semantics

---

## 8. Privacy Posture

- **Local-first by default.** All taste DNA, saved restaurants, and recent visits in LocalStorage in V1. Nothing leaves the device except the lat/lng pair sent to our Worker (which is itself proxied to Google Places).
- **Location is ephemeral on the server.** The Worker never logs lat/lng to persistent storage. Workers KV cache keys are rounded to ~110m grid cells, so even cache entries can't pinpoint individual users.
- **No analytics in V1.** No GA, no Mixpanel, no fingerprinting. The Worker logs only HTTP status codes and aggregate request counts for cost monitoring.
- **No third-party trackers** in cookies or scripts. No Google Tag Manager. No Facebook pixel.
- **Permission honesty.** Location primer copy explains exactly what we do with the coordinates: send to Google to find restaurants, never store them server-side.
- Settings has explicit **"Export my data"** (downloads JSON) and **"Delete everything"** (wipes LocalStorage).
- V2 backend: Supabase row-level security, no third-party data sharing, no behavior data sold ever. Privacy policy reads in plain English.

---

## 9. Acceptance Criteria for V1

**Frontend**
- [ ] App installs as PWA on iOS Safari and Android Chrome
- [ ] First contentful paint < 1.0s on 4G
- [ ] All 9 routes functional with **live restaurant data**
- [ ] Geolocation primer shown before browser permission dialog
- [ ] ZIP code fallback works when location is denied
- [ ] Reverse geocoded neighborhood name shown in top chip
- [ ] Swipe physics feel native (test on iPhone 14+ and Pixel 7+)
- [ ] Big Button delivers a recommendation in <500ms (cache hit) / <2s (cache miss)
- [ ] Taste DNA persists across sessions (LocalStorage)
- [ ] Maps deep links open Apple Maps on iOS, Google Maps on Android
- [ ] DoorDash deep links work (open app if installed, else web fallback)
- [ ] Group Sync works between two browser tabs via BroadcastChannel
- [ ] Loading states use skeletons, never spinners
- [ ] Zero red badges, zero streaks, zero notifications anywhere
- [ ] All color pairs pass WCAG AA contrast
- [ ] `prefers-reduced-motion` disables flips/springs
- [ ] Lighthouse: Performance ≥ 95, Accessibility = 100, Best Practices ≥ 95

**Worker / API**
- [ ] Cloudflare Worker deploys via `wrangler deploy`
- [ ] Google API key stored only as Worker secret, never in frontend
- [ ] Nearby Search returns only restaurants with `rating >= 4.0`
- [ ] FieldMask is set on every Places API request (no Enterprise-tier fields in V1)
- [ ] Workers KV caches Nearby results with 1-hour TTL on rounded location grid
- [ ] Photo proxy strips API key from URL before serving to client
- [ ] CORS allows only production origin and `localhost:*`
- [ ] Rate limit: 60 req/min per IP
- [ ] Worker handles Places API quota errors gracefully (returns 503 with friendly message for frontend)

---

## 10. Phased Roadmap

| Version | Scope | Timeline |
|---|---|---|
| **V1** (this prompt) | Single-file PWA + Cloudflare Worker, **live Google Places data**, real geolocation, all 10 features at MVP fidelity, LocalStorage only | 1–2 sprints |
| **V2** | React Native (Expo), Supabase backend, cross-device DNA sync, real Group Sync via Realtime, Routes API for travel times, DoorDash Drive integration | 6–8 weeks |
| **V3** | Apple Watch complication, iMessage extension, on-device ML taste prediction, Places API AI summaries | 8–12 weeks |

---

## 11. Build Approach for Claude Code

1. Read this entire prompt and confirm scope before writing code.
2. **Set up the Worker first.** Without it, the frontend has nothing to talk to.
   - `wrangler init worker`
   - Implement `/api/nearby`, `/api/place/{id}`, `/api/photo/{ref}`, `/api/geocode`
   - Set `GOOGLE_PLACES_KEY` as a secret
   - Test with `curl` from local before any frontend work
3. Build `index.html` with the design system tokens; verify in browser.
4. Wire geolocation primer + ZIP fallback before any other screen — everything depends on having a location.
5. Implement screens in this order: **Home → Swipe → Match → DNA → Saved → Group → Settings**.
6. Wire up the Big Button last — it ties together Taste DNA + Variety Memory + Context Engine.
7. After V1 is functional, write a `TESTING.md` with manual test cases for each route.
8. Commit progress in 8 logical chunks. Suggested chunks:

   1. **Worker scaffold** — `/api/nearby` with FieldMask + KV cache + rating filter
   2. **Worker complete** — `/api/place/{id}`, `/api/photo/{ref}`, `/api/geocode`, CORS, rate limit
   3. **Frontend shell** — design system tokens, routing, layout primitives
   4. **Geolocation flow** — primer, permission, ZIP fallback, neighborhood chip
   5. **Home screen + recommendation algorithm + Big Button** (now end-to-end with real data)
   6. **Swipe stack** with real cards
   7. **Match card + Maps/DoorDash deep links**
   8. **Taste DNA + Saved + Settings + Group Sync + PWA polish**

---

## 12. Out of Scope for V1

- Real auth / accounts (V2)
- Cross-device DNA sync (V2)
- Real cross-device Group Sync (V2 — V1 uses BroadcastChannel for multi-tab demo)
- Routes API for accurate travel times (V2 — V1 uses distance-based estimate)
- AI-powered place summaries from Places API (V3 — costs sit in Enterprise tier)
- Reservations (V3+)
- Reviews / writing reviews (never — too noisy)
- Photo uploads (never — staying calm)
- Social feed (never — staying calm)
- Push notifications (never default-on)

---

## 13. Done = Calm

The V1 is done when a stranger can:
1. Open the app
2. Allow location (or type a ZIP)
3. Tap "Decide for me"
4. Be on their way to a real, open, 4-star+ restaurant nearby

…in under 10 seconds, without anything ever feeling loud, busy, or demanding.

That's the bar.
