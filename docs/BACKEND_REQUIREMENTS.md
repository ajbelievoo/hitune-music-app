# HiTune Music — Backend Requirements

Ye document backend team ke liye hai. Flutter app mein saare client-side
features implement ho chuke hain; unke sahi working ke liye neeche diye gaye
endpoints / payload fields chahiye. Saare endpoints `POST` hain aur existing
BOF signing (`bof_signature`) ke through jaate hain — `ApiService` session
keys (`sess_id`/`sess_key` POST fields + `x-bof-sess-key` header +
`PHPSESSID` cookie) automatically bhejta hai.

## 1. Subscription plans & feature gating (ADMIN CONTROLLED)

`client_config` response mein yeh fields add karein:

```json
{
  "user": {
    "plan": "free | premium | family | ...",
    "is_premium": 1
  },
  "setting": {
    "default_plan": "free",
    "iap_enabled": true
  },
  "plan_features": {
    "free":    ["sleep_timer", "lyrics", "comments", "playlists", "recommendations"],
    "premium": ["offline_downloads", "hq_audio", "no_ads", "equalizer",
                "sound_controls", "casting", "unlimited_skips",
                "collaborative_playlists", "voice_search"]
  }
}
```

Feature keys jo app samajhta hai (`AppFeatures`):
`offline_downloads`, `lyrics`, `sleep_timer`, `equalizer`, `sound_controls`,
`hq_audio`, `no_ads`, `casting`, `unlimited_skips`, `comments`, `playlists`,
`recommendations`, `push_notifications`, `voice_search`,
`collaborative_playlists`.

Notes:
- `plan_features` list ya map (`{"lyrics": true}`) — dono accept hain.
- Agar `plan_features` na bheja jaye to app **fail-open** hai (sab allowed)
  taaki existing users lock na hon. Jab tak admin plan mapping set nahi karta,
  premium features free rahenge — isliye production launch se pehle yeh map
  zaroor configure karein.
- User ka plan `user.plan` / `user.data.plan` / `user.extra.plan` /
  `is_premium` — koi bhi ek field chalega.

## 2. Offline downloads

`muse_request_source` response mein ek naya field add karein:

```json
{ "download_url": "https://.../file.mp3" }
```

- Direct audio file URL ho (mp3/m4a/aac/ogg/flac) — HLS (m3u8/ts) download
  nahi ho sakta, app usko reject karta hai.
- Sirf premium users ke liye `download_url` return karein (plan_features ke
  hisaab se). Free users ke liye field omit karein.
- Client `track_lyrics` style object fields pass karta hai:
  `object_type`, `object_hash`.

## 3. Lyrics

Endpoint: `track_lyrics`
Request: `object_type`, `object_hash`
Response:

```json
{ "lyrics": "plain text ya LRC", "lrc": "optional synced lrc" }
```

Upload wizard already `lyrics` field bhejta hai (`upload_wizard`), bas fetch
endpoint chahiye. LRC format diya jaye to app time-synced highlighting add
kar sakta hai.

## 4. Playlists management

| Endpoint            | Fields                                              |
|---------------------|-----------------------------------------------------|
| `playlist_create`   | `playlist` (name) → return `{ "playlist_hash": "..." }` |
| `playlist_add`      | `playlist`, `object_type`, `object`                 |
| `playlist_remove`   | `playlist`, `object_type`, `object`                 |
| `playlist_rename`   | `playlist`, `name`                                  |
| `playlist_delete`   | `playlist`                                          |
| `playlist_reorder`  | `playlist`, `order` (comma-separated track hashes)  |
| `playlist_collab`   | `playlist`, `collab` (0/1), `invite` (user_id)      |

`user_library?tab=playlists` items mein `hash` (ya `id`) aur `count`
fields dena zaroori hai.

## 5. Notifications

| Endpoint                  | Fields                        | Returns                        |
|---------------------------|-------------------------------|--------------------------------|
| `notifications`           | `page`                        | `{ "items": [ {...} ] }`       |
| `notification_mark_read`  | `notification_id`             | ok                             |
| `notification_mark_all`   | —                             | ok                             |
| `push_register`           | `fcm_token`, `platform`       | ok                             |

Notification item fields: `id`, `title`, `body`, `image`, `link`,
`is_read` (0/1), `created_at` (unix ya ISO).

Push delivery ke liye Firebase Cloud Messaging — app mein FCM wiring ke liye
`google-services.json` / `GoogleService-Info.plist` aur `firebase_messaging`
package chahiye (client-side ready hai via `push_register`).

## 6. Comments

| Endpoint          | Fields                                     |
|-------------------|--------------------------------------------|
| `comments`        | `object_type`, `object`, `page`            |
| `comment_add`     | `object_type`, `object`, `text`            |
| `comment_delete`  | `comment_id`                               |

Comment item: `id`, `author`/`user.name`, `avatar`, `text`, `created_at`,
`likes`.

## 7. Recommendations / Made for you

Endpoints (koi bhi ho to rail render hogi, warna hidden):

| Endpoint                     | Returns                                  |
|------------------------------|------------------------------------------|
| `recommendations`            | `{ "items": [...] }`                     |
| `daily_mix`                  | `{ "items": [...] }`                     |
| `recommendations_because`    | `{ "items": [...] }` (seeded by history) |

Item shape = standard widget item (`hash`, `title`, `sub_title`, `cover`,
`object_type`).

## 8. In-app purchases / subscriptions

| Endpoint          | Fields                                             |
|-------------------|-----------------------------------------------------|
| `verify_purchase` | `product_id`, `purchase_token`, `platform`         |

Backend receipt verify karke user ka `plan` set kare. Products Play Console
(`hitune_premium_monthly`, `hitune_premium_yearly`) / App Store Connect mein
banane honge. `setting.iap_enabled=true` aane par hi app native billing UI
dikhayegi; warna external checkout (`UpgradePlansScreen`) use hota hai.

## 9. Radio

`/radios` response items mein in fields ka kam se kam ek zaroor ho:
`url` / `stream_url` (playable stream), `name`/`title`, `image`/`logo`.

## 10. Casting (Chromecast / AirPlay)

Pure client/native work — Google Cast SDK integrate karna hai. Backend se sirf
content URLs publicly reachable hone chahiye (signed URLs Cast receiver pe
expire nahi hone chahiye).

## 11. CarPlay / Android Auto

Android: manifest mein `automotive_app_desc.xml` + `MediaBrowserService`
already wired hai (audio_service). iOS CarPlay ke liye `com.apple.developer.
carplay-audio` entitlement + Apple approval chahiye — backend se sirf
browseable lists (home/user_library) ka stable JSON kaafi hai.

## 12. Analytics / reporting

Optional endpoints for artist dashboards: `track_stats`,
`artist_earnings`, `payout_request`. App mein `analytics_screen` exist
karta hai — in endpoints ke data se rich banega.

## 13. Account deletion

`settings` mein delete flow hai; confirm endpoint `user_delete`
(`password` field) jo pehle se `user_edit` tab `delete` mein partially
wired hai — verify karein ki final deletion call sahi endpoint pe ja rahi hai.

## 14. Per-track loudness normalization (Spotify-style) — HIGH PRIORITY

App mein client-side audio engine ready hai (equalizer, compressor, bass
boost, stereo widening — Android `DynamicsProcessing` ke through). Lekin
**har gaane ka volume alag-alag** hona fix karne ke liye backend se loudness
metadata chahiye. Yeh Spotify/YouTube Music/Apple Music sab karte hain —
"volume normalization" feature ka asli engine yehi hai.

### Kya karna hai

Upload/transcode pipeline mein har track measure karein:

```bash
ffmpeg -i input.mp3 -af ebur128=peak=true -f null -
```

Output se do values nikaalein:
- `I:` (integrated loudness, LUFS) — e.g. `-9.4`
- `Peak:` (true peak, dBTP) — e.g. `-0.3`

### Response mein bhejein

`muse_request_source` (aur `muse_solve_raaz`) response mein kisi bhi level pe
yeh fields rakhein — app poora payload scan karta hai:

```json
{ "loudness": { "lufs": -9.4, "peak_db": -0.3 } }
```

ya flat fields bhi chalte hain: `lufs` / `loudness_lufs` / `integrated_loudness`,
`peak_db` / `true_peak_db`, ya seedha `replaygain_db` / `track_gain` (already
computed gain ho to).

### Client behaviour (already implemented)

- App target `-14 LUFS` use karta hai (Spotify standard): `gain = -14 - lufs`
- True peak clamp: gain aisa ho ki peak −1 dBTP se upar na jaye (no clipping)
- Metadata na mile to gain 0 (koi change nahi) — fully backward compatible
- iOS pe volume-based fallback, Android pe LoudnessEnhancer

### Alternative (heavy option)

Chahein to transcode time pe hi normalize kar dein
(`ffmpeg -af loudnorm=I=-14:TP=-1.5:LRA=11`, 2-pass) — tab metadata bhejne ki
zaroorat nahi, par gain-only approach lossless hota hai aur user toggle kar
sakta hai, isliye metadata route better hai.

## 15. Public Developer API (third-party integrations)

HiTune ka ek public developer API banana hai — koi bhi third-party
website/app apne andar HiTune catalog search + play kar sake (Spotify for
Developers model). Pura detailed spec (public endpoints, embed player,
security, plans, rollout) `docs/DEVELOPER_API.md` mein hai. Neeche sirf
app-facing contract hai.

### `client_config` flag

```json
{ "setting": { "developer_portal": true } }
```

`developer_portal` true ho tabhi app Profile → "Developer API" menu dikhata
hai. Abhi tak backend pe nahi hai to menu hidden rehta hai (fail-hidden).

### App-facing endpoints (existing signed POST surface)

| Endpoint | Fields | Returns |
|---|---|---|
| `developer_plans` | — | `{ "plans": [...], "enabled": true }` — plan objects mein `hash/name/prices/quota/rate_limit/features` |
| `developer_apps` | — | `{ "apps": [{ "hash","name","status","plan","client_id","publishable_key","created_at" }] }` |
| `developer_app_create` | `name`, `website`, `platform` | `{ "app": {...}, "client_secret": "..." }` — **secret sirf is response mein ek baar dikhta hai** |
| `developer_app_update` | `hash`, `name`, `website` | ok |
| `developer_app_delete` | `hash` | ok |
| `developer_key_regenerate` | `hash`, `which` (`secret` ya `publishable`) | `{ "client_secret"? , "publishable_key"? }` |
| `developer_usage` | `hash`, `period` (optional `30d`) | `{ "daily": [{"date","requests","streams"}], "quota": {"used","limit"} }` |
| `developer_subscribe` | `plan_hash`, `app_hash` | payment link — `subscribe_link` hook ya koi bhi URL field (app broad-scan karti hai, `purchase_subs_plan` jaisa) |

### Plans (admin configurable)

Default tiers spec ke mutabiq: **Sandbox** (free, 10k req/mo, metadata +
previews + embed), **Starter** (100k req/mo, embed), **Pro** (1M req/mo,
direct stream API ≤192kbps), **Unlimited/Enterprise** (custom). Prices/quotas
`be/developer_plans_update` se admin control karta hai — app mein hardcode
mat karein, sab `developer_plans` response se render ho.

### DB tables

`developer_apps` (user_id, name, website, platform, status, plan_hash,
client_id, publishable_key_hash, secret_hash), `developer_usage`
(app_hash, date, requests, streams).
