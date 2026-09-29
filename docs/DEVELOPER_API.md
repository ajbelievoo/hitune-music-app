# HiTune Developer API — Specification

Ye document HiTune ka **public developer API** define karta hai — jaise Spotify
apna "Spotify for Developers" deta hai, waise hi koi bhi third-party
website/app apne platform ke andar HiTune ke songs search kar sake, metadata
dikha sake, aur (plan ke hisaab se) full tracks ya embed player play kar sake.

Backend team isko implement karegi. Frontend (Flutter app) sirf developer
portal UI deta hai (`lib/features/developer/`).

> **Legal note (important):** Third-party apps ko full-track streaming dene se
> pehle content licensing/rights confirm karein. Metadata + 30-second previews
> + embedded player (playback HiTune ke player ke through) sabse safe starting
> point hai — yehi model Spotify bhi follow karta hai.

---

## 1. Architecture

Do alag surfaces:

| Surface | Base URL | Auth | Kaun use karta hai |
|---|---|---|---|
| App API (existing) | `https://music.hitune.in/api/` | `bof_signature` + session | HiTune Flutter app |
| **Public Developer API (new)** | `https://music.hitune.in/api/v1/` | API key / OAuth token | Third-party devs |

Public API **REST-style GET/POST + JSON** hona chahiye (external devs ko BOF
signing samjhana possible nahi). Responses standard JSON, errors standard HTTP
codes ke saath.

## 2. Developer onboarding

1. Developer HiTune account banata hai (normal user account).
2. App ya web portal mein "Developer API" section se **app create** karta hai:
   `name`, `website` / `bundle_id`, `platform` (`web | android | ios | server`).
3. Backend generate karta hai:
   - `client_id` — public identifier (`ht_live_...` / `ht_test_...`)
   - `client_secret` — sirf server-to-server calls ke liye (ek baar dikhta hai)
   - `publishable_key` — browser/app mein embed karne layak, domain-restricted
4. App `pending` → `active` status mein jaata hai (auto-approve ya admin
   approval — admin setting `developer_auto_approve`).

## 3. Authentication

Do modes:

### 3a. Publishable key (client-side, read-only)

```
GET /api/v1/search?query=arijit
x-api-key: ht_pub_abc123
```

- Sirf metadata + previews + embed. Stream URLs nahi deti.
- `Referer`/`Origin` ya app bundle id registered list se match karna zaroori —
  nahi to `403`.

### 3b. Client credentials token (server-to-server)

```
POST /api/v1/token
grant_type=client_credentials&client_id=ht_live_xxx&client_secret=yyy

→ { "access_token": "...", "token_type": "bearer", "expires_in": 3600 }
```

Phir `Authorization: Bearer <token>` se calls. Isi mode se `stream` endpoint
khulta hai (plan-gated) — taaki secret leak hone pe bhi publishable key se
full tracks na nikle.

## 4. Public endpoints (v1)

Saare relative to `https://music.hitune.in/api/v1/`.

| Endpoint | Description |
|---|---|
| `GET /search?query=&type=track,album,artist,playlist&limit=&offset=` | Catalog search |
| `GET /tracks/{hash}` | Track metadata: title, artists, album, duration, covers, `preview_url` |
| `GET /albums/{hash}` | Album + track list |
| `GET /artists/{hash}` | Artist + top tracks + albums |
| `GET /playlists/{hash}` | Public playlist + tracks |
| `GET /charts?region=` | Trending/top lists |
| `GET /genres` | Genre list |
| `GET /tracks/{hash}/stream` | **Plan-gated.** Signed expiring stream URL |
| `GET /embed/{type}/{hash}` | iframe-ready HTML player (track/album/playlist) |
| `GET /oembed?url=` | oEmbed for auto-embeds (WordPress etc.) |

> **Search param `query` hai, `q` nahi.** `q` front-controller (`index.php`)
> ka route param hai — `?q=` bhejne pe path override ho jaata hai aur galat
> endpoint resolve hota hai. Hamesha `?query=` use karein.
>
> **Live status (verified 2026-09):** `search`, `tracks/{hash}` aur `token`
> production pe kaam kar rahe hain. Server OpenLiteSpeed hai (`.htaccess`
> process nahi hota) — `/api/v1/*` routing `index.php` ke andar handle hoti
> hai. Legacy `/api/blitz_search`, `/api/blitz_source`, `muse_request_source`
> internal signed endpoints hain — third-party apps ko sirf `/api/v1/` dena.

### `GET /tracks/{hash}` response shape

```json
{
  "hash": "T7xK2...",
  "title": "Song Name",
  "artists": [{"hash": "...", "name": "Artist"}],
  "album": {"hash": "...", "title": "...", "cover": "https://..."},
  "duration_ms": 214000,
  "explicit": false,
  "preview_url": "https://cdn.../preview.mp3",
  "links": {"hitune": "https://music.hitune.in/track/T7xK2..."}
}
```

### `GET /tracks/{hash}/stream` (Bearer token, plan >= Pro)

```json
{
  "url": "https://cdn.../audio?token=...",
  "expires_at": 1727000000,
  "expires_in": 14400,
  "quality": "192kbps",
  "loudness": {"lufs": -9.4, "peak_db": -0.3}
}
```

- URL **signed + expiring (4h)** hona chahiye — raw file path kabhi expose nahi.
- Free/Starter plan pe yeh endpoint `403 { "error": "plan_required" }` deta hai;
  unke liye `preview_url` (30s) aur embed player hi hai.
- Per-key stream quota alag se count hota hai (plan table neeche).

### Embed player

```
<iframe src="https://music.hitune.in/api/v1/embed/track/{hash}?key=ht_pub_..."
        width="100%" height="152" frameborder="0" allow="encrypted-media"></iframe>
```

Embed player HiTune ka branded player hai (play/pause, seek, "Open in HiTune"
link) — playback bytes HiTune CDN se hi jaate hain, isliye Starter plan pe bhi
full-track playback possible hai bina stream URL expose kiye. Yeh Spotify ke
embed jaisa hi model hai aur licensing-wise sabse safe hai.

## 5. API plans

Admin panel se fully configurable (`be/developer_plans`). Defaults:

| | **Sandbox** (free) | **Starter** | **Pro** | **Unlimited / Enterprise** |
|---|---|---|---|---|
| Price | ₹0 | ~₹999/mo | ~₹4,999/mo | Custom / contact sales |
| Requests/month | 10,000 | 100,000 | 1,000,000 | Unlimited (fair use) |
| Rate limit | 10 req/min | 60 req/min | 300 req/min | 1,000 req/min |
| Apps per account | 1 | 3 | 10 | Unlimited |
| Metadata + search | Yes | Yes | Yes | Yes |
| 30s previews | Yes | Yes | Yes | Yes |
| Embed player | Yes (branded) | Yes | Yes | Yes, white-label option |
| Direct stream API | No | No | Yes (≤192kbps) | Yes (≤lossless) |
| Monthly stream cap | — | — | 50,000 | Unlimited |
| Commercial use | No | Yes | Yes | Yes |
| Support | Community | Email | Priority | Dedicated + SLA |

Notes:
- "Unlimited" bhi fair-use + anti-abuse monitoring ke saath; truly uncapped
  sirf Enterprise contract pe.
- Quota over → `429` + `Retry-After`; monthly quota over → `402`/`quota_exceeded`.
- Paid plans ka purchase existing `purchase_subs_plan` flow reuse kar sakta hai
  (plan `type: "developer"`), ya alag `developer_subscribe` endpoint jo payment
  link return kare — app dono handle karta hai.

## 6. Rate limiting & quotas

Har response mein headers:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 58
X-RateLimit-Reset: 1727000000
X-Quota-Remaining: 98765   (monthly)
```

- Rate limit = per api key, sliding window.
- Usage counters daily aggregate hote hain (`developer_usage` table) — portal
  mein graph ke liye.

## 7. User-facing endpoints (app API — existing signed POST style)

Ye endpoints existing `/api/` surface pe aate hain taaki Flutter app developer
portal dikhha sake:

| Endpoint | Fields | Returns |
|---|---|---|
| `developer_plans` | — | `{ "plans": [...], "enabled": true }` |
| `developer_apps` | — | `{ "apps": [ {hash,name,status,plan,client_id,publishable_key,usage} ] }` |
| `developer_app_create` | `name`, `website`, `platform` | `{ app, client_secret }` (secret ek baar) |
| `developer_app_update` | `hash`, `name`, `website` | ok |
| `developer_app_delete` | `hash` | ok |
| `developer_key_regenerate` | `hash`, `which` (`secret`/`publishable`) | `{ client_secret? , publishable_key? }` |
| `developer_usage` | `hash`, `period` | `{ daily: [{date,requests,streams}], quota }` |
| `developer_subscribe` | `plan_hash`, `app_hash` | `{ link }` payment URL (ya `subscribe_link` hook) |

`client_config` mein flag add karein taaki app ka "Developer API" menu tabhi
dikhe jab backend ready ho:

```json
{ "setting": { "developer_portal": true } }
```

## 8. Admin panel endpoints (`/api/be/`)

| Endpoint | Kaam |
|---|---|
| `be/developer_apps` | Saare dev apps list + filter (status/plan) |
| `be/developer_app_approve` / `be/developer_app_suspend` | Lifecycle |
| `be/developer_plan_set` | Plan override / comp |
| `be/developer_plans_update` | Plan tiers, quotas, prices edit |
| `be/developer_usage_report` | Global usage analytics |
| `be/developer_tos_update` | Developer terms text |

Admin settings: `developer_auto_approve`, `developer_default_plan`,
`developer_portal_enabled`.

## 9. Security requirements

- `client_secret` hashed store ho (sha256), kabhi wapas plain na dikhe —
  sirf regenerate.
- Publishable keys pe domain/bundle allowlist **mandatory**.
- Stream URLs: signed token, ≤4h expiry, per-key stream quota.
- Anomaly detection: ek key se abnormal volume → auto-throttle + admin alert.
- Key revocation instant effective ho (cache ≤60s).
- Public API pe `x-bof-*` signing **nahi** chahiye — plain `x-api-key` ya Bearer.
- CORS: sirf registered origins pe `Access-Control-Allow-Origin`.

## 10. Errors

```json
{ "error": { "code": "quota_exceeded", "message": "Monthly quota exhausted",
             "plan": "starter", "upgrade_url": "https://..." } }
```

Codes: `invalid_key` (401), `forbidden` (403), `not_found` (404),
`rate_limited` (429), `quota_exceeded` (402), `plan_required` (403).

## 11. Developer terms (TOS) — must-have clauses

- "Powered by HiTune" attribution + logo link mandatory on free tier.
- Catalog data cache ≤24h; audio bytes kabhi re-host nahi.
- Full tracks sirf embed player ya signed stream se — ripping/record
  prohibited, violation pe instant revocation.
- HiTune catalog rights ka representation developer ke paas transfer nahi hota;
  commercial redistribution rights plan ke hisaab se.

## 12. Rollout phases

1. **Phase 1 (MVP):** keys + metadata/search + previews + embed player +
   Sandbox plan. Portal mein app create/key copy/usage count.
2. **Phase 2:** paid plans + quotas + direct stream API (Pro).
3. **Phase 3:** oEmbed, webhooks (quota alerts, track updates), white-label
   embeds, Enterprise.
