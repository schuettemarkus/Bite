# Bite Worker

Cloudflare Worker that proxies the Google Places API for the Bite app. Hides the API key, enforces a `rating >= 4.0` filter, normalizes Google's response into Bite's `Restaurant` model, and caches aggressively in Workers KV to keep API costs near zero for early-stage usage.

---

## What this Worker does

| Endpoint | Purpose |
|---|---|
| `GET /api/nearby?lat={n}&lng={n}&radius={m}` | Restaurants near user location, filtered to ≥4 stars |
| `GET /api/place/{placeId}` | Full details for the match view |
| `GET /api/photo/{encodedPhotoName}?maxWidth={n}` | Photo proxy — strips API key, 302 to signed Google URL |
| `GET /api/geocode?zip={code}` | ZIP / address → lat/lng (permission-denied fallback) |
| `GET /api/reverse-geocode?lat={n}&lng={n}` | Coords → neighborhood name (Home location chip) |
| `GET /health` | Liveness check |

All Places API requests use a `FieldMask` header to stay within the **Pro SKU tier**. Enterprise-only fields (reviews, generative summaries) are deliberately excluded — bring them back in V3 once unit economics are proven.

---

## Setup

### 1. Prerequisites

- Node.js 18+
- A Cloudflare account (free tier works)
- A Google Cloud project with **Places API (New)** and **Geocoding API** enabled
- An API key from that Google Cloud project, restricted to your Worker's domain

### 2. Install

```bash
cd worker
npm install
```

If you don't have `wrangler` globally:

```bash
npm install -g wrangler
wrangler login
```

### 3. Create the KV namespace

```bash
wrangler kv:namespace create CACHE
wrangler kv:namespace create CACHE --preview
```

Copy both returned IDs into `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "CACHE"
id = "abc123..."           # from first command
preview_id = "def456..."   # from second command
```

### 4. Set secrets

Production:

```bash
wrangler secret put GOOGLE_PLACES_KEY
# paste your Google API key when prompted
```

Local development:

```bash
cp .dev.vars.example .dev.vars
# edit .dev.vars and paste your key
```

### 5. Run locally

```bash
npm run dev
# Worker is now at http://localhost:8787
```

Test it:

```bash
curl http://localhost:8787/health
# → {"ok":true,"ts":1714000000000}

curl "http://localhost:8787/api/nearby?lat=37.7749&lng=-122.4194"
# → {"restaurants":[...],"cached":false}
```

### 6. Deploy

```bash
npm run deploy
```

Wrangler prints the deployed URL (something like `https://bite-worker.YOUR_SUBDOMAIN.workers.dev`). Set this as the API base URL in the frontend.

### 7. Lock down the Google API key

In Google Cloud Console → APIs & Services → Credentials → your key:
- **Application restrictions**: HTTP referrers → add only your Worker domain
- **API restrictions**: Restrict to *Places API (New)* and *Geocoding API*

This means even if the key leaks, it only works from your Worker.

---

## Configuration

### `wrangler.toml`

| Variable | Purpose | Where set |
|---|---|---|
| `ALLOWED_ORIGIN` | Production frontend origin allowed by CORS | `[vars]` block |
| `GOOGLE_PLACES_KEY` | Google Cloud API key | `wrangler secret put` |
| `CACHE` | KV namespace binding for caching + rate limit | `[[kv_namespaces]]` block |

`localhost:*` is allowed in CORS by default for development.

---

## Architecture

```
Browser (PWA)
  ↓
  ├─ /api/nearby?lat=..&lng=..       → Nearby Search (New)
  ├─ /api/place/{id}                 → Place Details (New)
  ├─ /api/photo/{ref}?maxWidth=..    → Place Photo (New)
  ├─ /api/geocode?zip=..             → Geocoding API (forward)
  └─ /api/reverse-geocode?lat=..&lng=..  → Geocoding API (reverse)
      ↓
  Worker
    │
    ├─ Rate limit (60/min/IP via KV)
    ├─ CORS check
    ├─ Cache lookup (KV, rounded location grid)
    │     ↓ miss
    └─ Google API (FieldMask-restricted)
         ↓
       normalize() → 4★ filter → cache → return
```

### Caching strategy

| Cache | Key shape | TTL | Notes |
|---|---|---|---|
| Nearby | `nearby:{lat3}:{lng3}:{radius}` | 1h | Rounded to ~110m grid; users in same neighborhood share cache |
| Place Details | `place:{placeId}` | 1h | Fetched lazily on match |
| Photo signed URL | `photo:{name}:{w}` | 50min | Google's signed URLs expire ~1h, refresh before |
| Geocode (forward) | `geocode:{address}` | 30d | ZIP codes don't move |
| Reverse geocode | `revgeo:{lat2}:{lng2}` | 7d | Rounded to ~1km grid |
| Rate limit | `rl:{ip}` | 2min | Sliding window |

### Privacy

- Raw user coordinates are **never logged** to persistent storage.
- KV cache keys round coordinates to ~110m (Nearby) or ~1km (reverse geocode) — even cache contents can't pinpoint a user.
- The Worker logs only HTTP status codes and aggregate counts, sampled via Cloudflare Observability.

---

## Cost notes

With the caching layout above, expected per-user-day API spend (early-stage solo usage):

- 2–4 location refreshes/day × 1 Nearby Search call (only on cache miss)
- ~2 Place Details calls (lazy on match)
- ~5 Photo proxies (lazy as cards surface)
- 0–1 reverse geocode calls

Most days, repeat queries from the same neighborhood = **zero API calls** because the cache grid is shared across all users in that grid cell.

Google's free monthly tier (10K Essentials, 5K Pro events) covers solo dev/test usage indefinitely. A consumer rollout to thousands needs the V2 backend with proper authenticated tile caching across users — but that's V2's problem.

For belt-and-suspenders cost protection, set a **Google Cloud billing budget alert** at $5 / $20 / $100 thresholds.

---

## API reference

### `GET /api/nearby`

**Query params:**
- `lat` (required, float, -90..90)
- `lng` (required, float, -180..180)
- `radius` (optional, int meters, default 5000, max 50000)

**Response 200:**
```json
{
  "restaurants": [
    {
      "id": "ChIJ...",
      "name": "Tartine Bakery",
      "cuisine": "Bakery",
      "cuisineCategory": "cafe",
      "priceLevel": 2,
      "rating": 4.6,
      "reviewCount": 3421,
      "distance": 0.8,
      "travelTimeMin": 3,
      "imagePath": "/api/photo/places%2F...?maxWidth=800",
      "imageAlt": "Tartine Bakery photo",
      "tags": ["bakery", "cozy"],
      "address": "600 Guerrero St, San Francisco, CA",
      "openNow": true,
      "pickup": true,
      "delivery": false,
      "dineIn": true,
      "doorDashUrl": "https://www.doordash.com/search/store/Tartine%20Bakery",
      "mapsUrl": "https://maps.google.com/?cid=...",
      "phone": "+1 415-487-2600",
      "website": "https://tartinebakery.com",
      "lat": 37.7615,
      "lng": -122.4239
    }
  ],
  "cached": false
}
```

The frontend prepends the Worker's origin to `imagePath` to fetch photos.

### `GET /api/place/{placeId}`

Returns the raw Place Details response (the frontend can pass it through `normalizePlace` if the Restaurant shape is needed).

### `GET /api/photo/{encodedPhotoName}`

Returns a 302 redirect to a signed Google URL. The signed URL contains no API key. The frontend can use this directly in `<img src>`.

### `GET /api/geocode?zip={code}` / `?address={...}`

```json
{
  "lat": 37.7749,
  "lng": -122.4194,
  "formatted": "San Francisco, CA 94103, USA",
  "neighborhood": "South of Market"
}
```

### `GET /api/reverse-geocode?lat={n}&lng={n}`

```json
{
  "neighborhood": "Mission District",
  "city": "San Francisco",
  "region": "CA"
}
```

---

## Errors

| Status | Meaning |
|---|---|
| 400 | Bad request — invalid coordinates or place id |
| 403 | Disallowed origin (CORS) |
| 404 | Endpoint not found, or geocode/photo not found |
| 429 | Rate limited (60/min/IP) — `Retry-After: 60` header included |
| 503 | Upstream Google API error or quota |
| 500 | Unhandled error (logged to Cloudflare Observability) |

All error bodies are JSON: `{ "error": "human readable message" }`.

---

## Manual verification checklist

After deploy:

- [ ] `GET /health` returns `{ ok: true }`
- [ ] `GET /api/nearby?lat=37.7749&lng=-122.4194` returns ≥1 restaurant, all `rating >= 4.0`
- [ ] Same call again returns `"cached": true`
- [ ] Image path in response loads when prepended with Worker origin
- [ ] `GET /api/geocode?zip=94103` returns SF coords
- [ ] `GET /api/reverse-geocode?lat=37.7749&lng=-122.4194` returns "South of Market" or similar
- [ ] CORS preflight from frontend domain returns 204 with proper headers
- [ ] Request from a non-allowed Origin returns 403
- [ ] 61st request in 60 seconds returns 429
- [ ] Google API key is **never** present in any response body

---

## Observability

Tail live logs:

```bash
npm run tail
```

Filter for errors:

```bash
wrangler tail --status error
```

Cloudflare's Workers dashboard shows per-route latency, error rate, and KV hit ratio. Watch the KV hit ratio — it should climb above 70% within a day of normal use, which is what makes the cost math work.

---

## File map

```
worker/
├── src/
│   ├── index.js       # entry, router, error catching
│   ├── nearby.js      # /api/nearby — Nearby Search + 4★ filter + KV cache
│   ├── place.js       # /api/place/{id} — Place Details lazy load
│   ├── photo.js       # /api/photo/{ref} — photo proxy, signed URL caching
│   ├── geocode.js     # /api/geocode + /api/reverse-geocode
│   ├── places.js      # Google API client (one place to change endpoints)
│   ├── normalize.js   # Google Place → Bite Restaurant shape
│   ├── cors.js        # origin allowlist
│   ├── ratelimit.js   # KV-backed sliding window
│   └── http.js        # JSON response helpers
├── wrangler.toml      # Cloudflare config
├── package.json       # scripts
├── .dev.vars.example  # template for local secrets
├── .gitignore
└── README.md
```

Total: ~600 LOC across 10 small files. Designed to be read top-to-bottom in one sitting.
