# HiTune Backend Team - Share Link Fix Required

## Problem Summary
Share links from Flutter app are returning **404 errors** when opened in browser.

## Root Cause Identified
The `/api/client/share` endpoint is generating **slug-based URLs** instead of **hash-based URLs**.

### Current (Broken) Response
```json
{
  "item": {
    "url": "https://music.hitune.in/music/track/rohitak_rock-fazeeta-fazeeta"
  }
}
```

### Required (Correct) Response
```json
{
  "item": {
    "url": "https://music.hitune.in/music/track/c0038bf550c33b4554c6268ee3efefa6/"
  }
}
```

## Files to Modify

### 1. File: `backend/api/app/client/endpoints/endpoint_share.php`
**Location:** Line 75-91

**Current Code:**
```php
$item_data = bof()->seo->fetch( array(
  "object" => $object_name,
  "item" => $object_item2,
  "lang" => null,
), true );
```

**Required Change:**
The URL from `bof()->seo->fetch()` uses slugs. You need to override it to use hash-based format:

```php
$item_data = bof()->seo->fetch( array(
  "object" => $object_name,
  "item" => $object_item2,
  "lang" => null,
), true );

// Override URL to use hash-based format instead of slug-based
if ( isset( $item_data["url"] ) && $object_hash ){
  // Build hash-based URL: /music/{type}/{hash}/
  $type_map = array(
    "m_track" => "track",
    "m_album" => "album", 
    "m_artist" => "artist"
  );
  $url_type = isset( $type_map[$object_name] ) ? $type_map[$object_name] : str_replace( "m_", "", $object_name );
  $item_data["url"] = "https://music.hitune.in/music/" . $url_type . "/" . $object_hash . "/";
}
```

### 2. Verify Share Redirect Endpoint
**File:** `backend/api/app/client/endpoints/endpoint_music_share_redirect.php`

Ensure this endpoint handles hash-based URLs correctly. It should:
1. Accept URLs like `/music/track/{32-char-hash}/`
2. Look up the object by hash
3. Redirect to the correct page

**Current implementation should already work** - just verify the regex pattern matches hash format.

## Testing Steps

1. Call share API:
```bash
curl -X POST https://music.hitune.in/api/client/share \
  -d "object_type=m_track" \
  -d "object_hash=c0038bf550c33b4554c6268ee3efefa6" \
  -d "sess_id=YOUR_SESSION"
```

2. Verify response contains hash-based URL:
```json
{
  "item": {
    "url": "https://music.hitune.in/music/track/c0038bf550c33b4554c6268ee3efefa6/"
  }
}
```

3. Open the URL in browser - should show track page, NOT 404.

## Key Points

- **Hash format:** 32-character hexadecimal (e.g., `c0038bf550c33b4554c6268ee3efefa6`)
- **URL pattern:** `https://music.hitune.in/music/{type}/{hash}/`
- **Object types:** `m_track` → `track`, `m_album` → `album`, `m_artist` → `artist`

## Contact
Flutter app is already sending correct hash in API call. Backend needs to return correct hash-based URL.

---
**Reported by:** Flutter Dev Team  
**Priority:** High (Production Issue)  
**Date:** March 23, 2026
