# Bite — Web App

Single-file PWA. Mobile-first. Talks to the Bite Worker for live restaurant data.

## Run locally

You need a local web server (the app uses ES module-free vanilla JS, but `fetch` to the Worker requires HTTP, not `file://`).

```bash
cd web
python3 -m http.server 5500
# or: npx serve .
# or any static file server
```

Open http://localhost:5500.

## Configure the Worker URL

Open `index.html`, find the `Config` object near the top of the `<script>` block, and replace `YOUR_SUBDOMAIN` with your deployed Worker subdomain:

```js
const Config = {
  WORKER_URL: location.hostname === 'localhost'
    ? 'http://localhost:8787'
    : 'https://bite-worker.YOUR_SUBDOMAIN.workers.dev',
  ...
};
```

For local dev, just run the Worker (`npm run dev` in `../worker`) on port 8787 and the app picks it up automatically.

## Icons

The manifest references icons in `/icons/`. Generate three PNGs:
- `icon-192.png` — 192×192
- `icon-512.png` — 512×512
- `icon-maskable.png` — 512×512 with safe zone padding

Until you add them, the PWA install prompt won't appear, but the app still runs fine.

## Deploy

Any static host works: Cloudflare Pages, Vercel, Netlify, GitHub Pages.

For Cloudflare Pages (free tier, easiest):

```bash
cd web
npx wrangler pages deploy . --project-name=bite
```

Then update `Config.WORKER_URL` in `index.html` to point at your production Worker domain, and update `ALLOWED_ORIGIN` in the Worker's `wrangler.toml` to point at your Pages domain.

## What's in here

```
web/
├── index.html         # the entire app — HTML + CSS + JS in one file
├── manifest.json      # PWA manifest
├── service-worker.js  # offline shell cache
└── icons/             # PWA icons (you provide)
```

`index.html` contains:
- Design system (CSS custom properties)
- Routing (hash-based)
- Storage (LocalStorage wrappers)
- API client (talks to Worker)
- Location handling (browser geolocation + ZIP fallback)
- Recommendation algorithm (scoring, filters, mode bias)
- 7 views: Home, Swipe, Match, DNA, Saved, Group, Settings
- Spring-physics swipe gestures
- BroadcastChannel-based Group Sync
- Haptics, toasts, modals
