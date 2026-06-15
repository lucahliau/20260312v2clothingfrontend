# TestFlight checklist

The app's bundle id is now **`com.clothedd.app`** (was the mangled
`organizationname.-0260312v2clothingfrontend`). The bundle id is permanent
once the first build is uploaded to App Store Connect — if you want a
different one, change it BEFORE doing anything below
(`PRODUCT_BUNDLE_IDENTIFIER` in project build settings, 2 occurrences).

## Side effects of the bundle id change (already true on your dev devices)

- The app installs as a NEW app: old install keeps its icon, Keychain tokens
  and UserDefaults don't carry over → log in again, delete the old app.
- Sign in with Apple, push, and universal links are keyed to the new id —
  the backend env updates below are REQUIRED or those features 503/break.

## 1. Railway env updates (backend service) — do these first

| Variable | New value |
|---|---|
| `APPLE_CLIENT_ID` | `com.clothedd.app` — or `com.clothedd.app,organizationname.-0260312v2clothingfrontend` to keep old installed builds signing in too (comma-separated list supported). **Currently UNSET → Apple Sign-In 503s.** |
| `APNS_BUNDLE_ID` | `com.clothedd.app` |
| `APPLE_UNIVERSAL_LINK_APP_ID` | `5ZZSUFNDX9.com.clothedd.app` |

Remote push also needs (if not already set): `APNS_KEY_ID`, `APNS_TEAM_ID`
(`5ZZSUFNDX9`), and `APNS_KEY_PATH` (the .p8 key file must be available to
the Railway container).

## 2. Apple Developer portal (developer.apple.com)

1. Certificates, IDs & Profiles → Identifiers → register App ID
   `com.clothedd.app` with capabilities: **Push Notifications**,
   **Sign in with Apple**, **Associated Domains**.
2. Keys → create an **APNs key** (.p8) if none exists; note its Key ID →
   feeds `APNS_KEY_ID` / `APNS_KEY_PATH` above.

## 3. App Store Connect

1. Apps → "+" → New App → platform iOS, bundle id `com.clothedd.app`,
   name "Clothedd" (or final name — the public name can differ from the
   project name).
2. Fill in the privacy policy URL (required for TestFlight external testers;
   internal testers can start without review).

## 4. Archive & upload (Xcode)

1. Open the project, select target → Signing & Capabilities → team
   `5ZZSUFNDX9`, automatic signing. Xcode will prompt to register the
   capabilities on the App ID if step 2 was skipped.
2. Product → Archive (Any iOS Device arm64) → Distribute App → TestFlight.
3. `aps-environment` is `development` in the entitlements file; the App
   Store export rewrites it to `production` automatically.

## 5. Smoke test on the TestFlight build

- Login (email + Sign in with Apple), feed swiping, brand pages.
- Push: send a DM from a second account → notification arrives on device
  (pushes don't reach simulators; use a real device).
- Universal link: open
  `https://20260311-clothes-backend-production.up.railway.app/...` item link
  → app opens (AASA is served by the backend using
  `APPLE_UNIVERSAL_LINK_APP_ID`).
