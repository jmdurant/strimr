# Slingshot — TestFlight Deployment Guide

## Current Status

The paid Apple Developer account (`ADVQS8RXPZ`, DoctorDuRant, LLC) is set up. The App Store Connect account is newly created and may need time to fully propagate before API uploads work.

### MCP Server

An App Store Connect MCP server is configured at `/Users/jamesdurant/asc-mcp-server` and registered in Claude Code's global settings. Once the account finishes propagating, Claude can handle the entire deployment flow via natural language.

**Quick test:** Ask Claude to run `check_agreement_status` — when it returns success, the account is ready.

---

## All 9 Apps

| # | App | Platform | Bundle ID | Project Path | Archive Status | Blocker |
|---|---|---|---|---|---|---|
| 1 | Slingshot | iOS | `com.doctordurant.slingshot` | `/Users/jamesdurant/strimr` | Ready | ASC propagation |
| 2 | Slingshot | tvOS | `com.doctordurant.slingshot` | `/Users/jamesdurant/strimr` | Needs archive | ASC propagation |
| 3 | Slingshot | macOS | `com.doctordurant.slingshot.macos` | `/Users/jamesdurant/strimr` | Needs archive | ASC propagation |
| 4 | Slingshot | watchOS | `com.doctordurant.slingshot.watchos` | `/Users/jamesdurant/strimr` | Ready | ASC propagation |
| 5 | Slingshot | visionOS | `com.doctordurant.slingshot.visionos` | `/Users/jamesdurant/strimr` | Needs archive | visionOS 26.2 SDK not installed |
| 6 | XMWatch | watchOS | `com.doctordurant.xmwatch.watchos` | `/Users/jamesdurant/XMWatch/XMWatch-watchOS` | Needs archive | No device registered |
| 7 | XMWatch | iOS | `com.doctordurant.xmwatch.ios` | `/Users/jamesdurant/XMWatch/XMWatch-iOS` | Needs archive | Missing Release build config |
| 8 | SameDayTrips | iOS | `com.doctordurant.tripassistant` | `/Users/jamesdurant/SameDayClt/same_day_trips_app` | Needs archive (Flutter) | No device registered |
| 9 | SameDayTripsWatch | watchOS | `com.doctordurant.tripassistant.watchkitapp` | `/Users/jamesdurant/SameDayClt/SameDayTripsWatch` | Needs archive | No device registered |

---

## Next Steps

### Step 1: Wait for ASC Propagation
New accounts can take a few hours to 24 hours. Test with:
```bash
xcrun altool --list-providers -u james@doctordurant.com -p "<app-specific-password>"
```
Or ask Claude: "Check agreement status"

### Step 2: Register a Device
Apps 6-9 need at least one registered device for provisioning. Either:
- Connect an iPhone via USB and open Xcode > Window > Devices and Simulators
- Or ask Claude: "Register my iPhone with UDID ___"

### Step 3: Register Bundle IDs
Ask Claude: "Register all these bundle IDs for my apps" and provide the list above. Or:
```
register_bundle_id com.doctordurant.slingshot IOS
register_bundle_id com.doctordurant.slingshot.macos MAC_OS
register_bundle_id com.doctordurant.slingshot.watchos IOS
register_bundle_id com.doctordurant.slingshot.visionos IOS
register_bundle_id com.doctordurant.xmwatch.watchos IOS
register_bundle_id com.doctordurant.xmwatch.ios IOS
register_bundle_id com.doctordurant.tripassistant IOS
register_bundle_id com.doctordurant.tripassistant.watchkitapp IOS
```

### Step 4: Create Apps in App Store Connect
Ask Claude: "Create all my apps in App Store Connect" — the MCP server handles this via the API now, no manual web UI needed.

### Step 5: Upload Builds
Ask Claude: "Upload Slingshot iOS to TestFlight" — the `upload_build` tool handles archive → export → upload.

### Step 6: Add Testers
Ask Claude: "Create a beta group and add me as a tester"

---

## Remaining Fixes Before Upload

### CarPlay Entitlement (Slingshot iOS)
Commented out in `Slingshot-iOS/Slingshot-iOS.entitlements` — needs Apple approval.
Apply at: https://developer.apple.com/contact/carplay

### XMWatch iOS — Missing Release Config
`/Users/jamesdurant/XMWatch/XMWatch-iOS/project.yml` only has a Debug build config. Need to add Release config and regenerate with `xcodegen`.

### visionOS SDK
Install visionOS 26.2 platform in Xcode > Settings > Components.

### SameDayTrips iOS (Flutter)
Requires `flutter build ipa --release` instead of xcodebuild. The MCP `upload_build` tool uses xcodebuild, so Flutter builds need a manual archive step or a custom script.

---

## Key Files

| File | Purpose |
|---|---|
| `Config/Config.xcconfig` | Team ID and bundle identifier |
| `Slingshot-iOS/Slingshot-iOS.entitlements` | iOS entitlements (CarPlay commented out) |
| `~/Desktop/slingshot-archives/ExportOptions.plist` | Export options for app-store-connect |
| `~/Downloads/AuthKey_538V7WB29X.p8` | App Store Connect API key |
| `~/.claude/settings.json` | MCP server configuration |

## Authentication

| Method | Credentials |
|---|---|
| API Key | Key ID: `538V7WB29X`, Issuer: `a2909df4-ea46-47c4-a6e0-09d7a870b794` |
| Apple ID | `james@doctordurant.com` + app-specific password |
| Distribution Cert | `Apple Distribution: DoctorDuRant, LLC (ADVQS8RXPZ)` |
