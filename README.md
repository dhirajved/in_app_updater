# in_app_updater

A Flutter plugin that prompts users to update your app using each platform's
native update mechanism — no custom backend or version API required:

- **Android** — wraps Google Play Core's [In-App Update API](https://developer.android.com/guide/playcore/in-app-updates) for **immediate** (full-screen, blocking) and **flexible** (background download + "restart to install" prompt) update flows.
- **iOS** — looks up your app's live App Store listing via Apple's public iTunes Lookup API and compares versions, then opens the App Store page in a StoreKit sheet (or Safari as a fallback).

It ships two layers you can use independently:

| Layer | What it's for |
|---|---|
| `UpdateChecker` widget | Drop-in, "just works" UI: wraps your home screen, checks for an update on launch, and shows a platform-appropriate dialog automatically. |
| `NativeUpdateService` | Low-level method-channel API if you want to build fully custom UI/flow. |

## Table of contents

- [Installation](#installation)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [API reference](#api-reference)
  - [`UpdateChecker` widget](#updatechecker-widget)
  - [`NativeUpdateService`](#nativeupdateservice)
  - [`UpdateCheckResult`](#updatecheckresult)
  - [`InstallStatus`](#installstatus)
- [Customizing the UI](#customizing-the-ui)
- [Full manual-flow example](#full-manual-flow-example)
- [Platform behavior differences](#platform-behavior-differences)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

## Installation

```yaml
dependencies:
  in_app_updater: ^0.0.1
```

```
flutter pub get
```

## Platform setup

**Android** — nothing to configure. The plugin bundles the Play Core
`app-update` dependency itself; `checkForUpdate`/`startImmediateUpdate`/
`startFlexibleUpdate` only return real data when the app was **installed from
the Play Store** (internal/closed/open testing tracks work too) — a debug
build run from Android Studio or `flutter run` will report
`updateAvailable: false` (or throw) since Play Core has nothing to compare
against.

**iOS** — nothing to configure either. `checkForUpdate` calls
`https://itunes.apple.com/lookup?bundleId=<your bundle id>` over HTTPS (no
App Transport Security exception needed) and only returns a real result once
your app has **at least one version live on the App Store** under that bundle
ID — a fresh app that has never been submitted will get a `PARSE_FAILED`
error (see [Troubleshooting](#troubleshooting)).

No Android manifest or iOS `Info.plist` changes are required for either
platform.

## Quick start

Wrap the widget you want the update flow to run against (typically your
app's home screen) in `UpdateChecker`:

```dart
import 'package:flutter/material.dart';
import 'package:in_app_updater/in_app_updater.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: UpdateChecker(child: HomePage()),
    );
  }
}
```

That's it. On launch, `UpdateChecker`:

1. Silently calls `checkForUpdate()` once (after the first frame).
2. If an update is available, shows a default `AlertDialog` ("Update
   available" / "Later" / "Update").
3. If the user taps **Update**:
   - **Android**: starts Play Core's immediate flow if the update is
     high-priority (`immediateAllowed`), otherwise the flexible
     background-download flow (`flexibleAllowed`); once the flexible download
     finishes, a `SnackBar` with a **RESTART** action appears to complete the
     install.
   - **iOS**: opens the App Store listing in a StoreKit sheet.

Any error from the native side (no network, app not installed from a store
build, etc.) is caught internally and the check is simply skipped — it will
never crash your app or block your UI.

## API reference

### `UpdateChecker` widget

```dart
UpdateChecker({
  required Widget child,
  UpdateDialogBuilder? androidUpdateDialogBuilder,
  UpdateDialogBuilder? iosUpdateDialogBuilder,
  AndroidRestartSnackBarBuilder? androidRestartSnackBarBuilder,
})
```

| Parameter | Type | Description |
|---|---|---|
| `child` | `Widget` | **Required.** The widget tree rendered underneath (typically your home screen). `UpdateChecker` renders `child` unmodified — it only adds the update-check side effect and an overlaid dialog/snackbar. |
| `androidUpdateDialogBuilder` | `UpdateDialogBuilder?` | Replaces the default dialog shown on Android when an update is found. Leave `null` to use the built-in `AlertDialog`. |
| `iosUpdateDialogBuilder` | `UpdateDialogBuilder?` | Same, for iOS. |
| `androidRestartSnackBarBuilder` | `AndroidRestartSnackBarBuilder?` | Replaces the default `SnackBar` shown on Android once a flexible update has finished downloading and is ready to install. |

**What it does internally** (for reference — you don't need to call any of
this yourself):

- On `initState`, schedules a `checkForUpdate()` call for right after the
  first frame (via `WidgetsBinding.addPostFrameCallback`), so it never runs
  before a `BuildContext`/`Navigator`/`ScaffoldMessenger` is available.
- If `result.updateAvailable` is `false`, or the widget was already disposed
  by the time the async check returns, it does nothing.
- On Android, it only shows a dialog if `immediateAllowed` or
  `flexibleAllowed` is `true` (an update can be "available" per the Play
  Store without either rollout type being enabled yet for this device).
- Cancels its install-state stream subscription in `dispose()`.

```dart
typedef UpdateDialogBuilder = Widget Function(
  BuildContext context,
  UpdateCheckResult result,
  VoidCallback onUpdate, // call to start the native update flow
  VoidCallback onLater,  // call to dismiss without updating
);

typedef AndroidRestartSnackBarBuilder = SnackBar Function(
  BuildContext context,
  VoidCallback onRestart, // call to install the downloaded update & restart
);
```

Example — custom Android dialog and restart snackbar:

```dart
UpdateChecker(
  androidUpdateDialogBuilder: (context, result, onUpdate, onLater) {
    return AlertDialog(
      title: const Text('New version available'),
      content: const Text('Update now for the latest features and fixes.'),
      actions: [
        TextButton(onPressed: onLater, child: const Text('Not now')),
        FilledButton(onPressed: onUpdate, child: const Text('Update')),
      ],
    );
  },
  androidRestartSnackBarBuilder: (context, onRestart) {
    return SnackBar(
      content: const Text('Update downloaded.'),
      action: SnackBarAction(label: 'Restart', onPressed: onRestart),
      duration: const Duration(days: 1),
    );
  },
  child: const HomePage(),
)
```

### `NativeUpdateService`

The method-channel bridge `UpdateChecker` is built on. Use it directly if you
want full control over the UI/timing instead of the built-in dialog flow.

```dart
final service = NativeUpdateService();
```

| Method | Platforms | Returns | Description |
|---|---|---|---|
| `checkForUpdate()` | Android, iOS | `Future<UpdateCheckResult>` | Queries whether an update is available. **Always call this first** — on iOS it also caches the App Store listing URL that `openStore()` later opens. Throws a `PlatformException` on failure (see error codes below). |
| `startImmediateUpdate()` | Android only | `Future<bool>` | Starts Play Core's **immediate** flow: a full-screen, blocking, Google-rendered update UI. The returned `Future` resolves once the user completes or cancels the flow (`true`/`false` = `Activity.RESULT_OK`/otherwise) — it does **not** wait for install to finish, since Play Core restarts the app itself on success. No-op / throws if no immediate update is allowed. |
| `startFlexibleUpdate()` | Android only | `Future<bool>` | Starts Play Core's **flexible** flow: downloads the update in the background while the user keeps using the app. Resolves once the user accepts/declines the confirmation dialog Play Core shows — not once the download finishes. Listen to `installStateStream()` to know when the download completes. |
| `completeFlexibleUpdate()` | Android only | `Future<void>` | Installs a flexible update that has finished downloading and restarts the app. Call this only after `installStateStream()` emits `InstallStatus.downloaded` (calling it earlier is a no-op on the native side). |
| `openStore()` | iOS only | `Future<bool>` | Opens the App Store listing found by the last `checkForUpdate()` call, as an in-app `SKStoreProductViewController` sheet; falls back to `UIApplication.open` (leaves your app) if no view controller is available to present from. Throws if `checkForUpdate()` hasn't been called yet (no cached URL). |
| `installStateStream()` | Android only | `Stream<Map<String, dynamic>>` | Broadcast stream of Play Core install-state events while a flexible update downloads. Each event is `{'status': String, 'bytesDownloaded': int, 'totalBytesToDownload': int}`. Safe to call multiple times — it lazily creates and reuses a single underlying stream. |
| `statusFromString(String? status)` | — | `InstallStatus` | Parses the `'status'` field of an `installStateStream()` event into an `InstallStatus` enum value (falls back to `InstallStatus.unknown` for anything unrecognized). |

Method channel error codes you may need to catch:

| Code | Platform | Meaning |
|---|---|---|
| `NO_ACTIVITY` | Android | Plugin isn't attached to an `Activity` yet (called too early, or during a transient detach). |
| `CHECK_FAILED` | Android, iOS | The Play Store / iTunes Lookup network call failed. |
| `UPDATE_NOT_AVAILABLE` | Android | `startImmediateUpdate`/`startFlexibleUpdate` called for an update type that isn't currently allowed. |
| `START_FAILED` | Android | Play Core couldn't launch its confirmation UI (`IntentSender.SendIntentException`). |
| `BAD_CONFIG` | iOS | Couldn't read the app's bundle ID or version from `Info.plist`. |
| `PARSE_FAILED` | iOS | The iTunes Lookup response didn't contain the expected fields (commonly: app not yet published, or not available in the lookup's storefront — see [Known limitations](#known-limitations)). |
| `NO_URL` | iOS | `openStore()` was called before a successful `checkForUpdate()`. |

### `UpdateCheckResult`

Return value of `checkForUpdate()`.

```dart
class UpdateCheckResult {
  final bool updateAvailable;
  final bool immediateAllowed;  // Android only
  final bool flexibleAllowed;   // Android only
  final String? currentVersion; // iOS only
  final String? latestVersion;  // iOS only
}
```

| Field | Populated on | Meaning |
|---|---|---|
| `updateAvailable` | both | Whether a newer version exists. |
| `immediateAllowed` | Android | Whether Play Core allows the blocking "immediate" flow for this update (usually true for high-priority releases). Always `false` on iOS. |
| `flexibleAllowed` | Android | Whether Play Core allows the background-download "flexible" flow. Always `false` on iOS. |
| `currentVersion` | iOS | The running app's `CFBundleShortVersionString`. `null` on Android. |
| `latestVersion` | iOS | The version currently live on the App Store. `null` on Android. |

### `InstallStatus`

Mirrors Play Core's `InstallStatus` (Android-only concept):

```dart
enum InstallStatus {
  pending, downloading, downloaded, installing, installed,
  failed, canceled, unknown,
}
```

`downloaded` is the one you generally act on — it means the flexible update
is ready and you should prompt the user to restart via
`completeFlexibleUpdate()`.

## Customizing the UI

Both dialog builders and the snackbar builder receive ready-to-call
callbacks (`onUpdate`, `onLater`, `onRestart`) — you never need to touch
`NativeUpdateService` yourself when using them; return whatever widget you
like (a `Dialog`, a custom `Container`-based sheet via `showDialog`'s
builder, etc.) and just wire the buttons to the callbacks:

```dart
UpdateChecker(
  iosUpdateDialogBuilder: (context, result, onUpdate, onLater) {
    return CupertinoAlertDialog(
      title: const Text('Update available'),
      content: Text(
        'Version ${result.latestVersion} is available. '
        'You have ${result.currentVersion}.',
      ),
      actions: [
        CupertinoDialogAction(onPressed: onLater, child: const Text('Later')),
        CupertinoDialogAction(
          onPressed: onUpdate,
          isDefaultAction: true,
          child: const Text('Update'),
        ),
      ],
    );
  },
  child: const HomePage(),
)
```

## Full manual-flow example

If you don't want the automatic on-launch dialog — e.g. you want your own
dialog widget, your own state management, or to trigger the check from
somewhere other than app launch (a "Check for updates" button in Settings) —
call `NativeUpdateService` directly instead of using `UpdateChecker`.

The example app's `ManualUpdateFlowPage`
([`example/lib/manual_update_flow_page.dart`](example/lib/manual_update_flow_page.dart))
is a runnable version of this pattern with a custom dialog, correct
immediate/flexible branching, and the install-state listener wired up — open
the example app and tap **"Open manual-flow example"** to see it. Short
version:

```dart
import 'dart:io';
import 'package:in_app_updater/in_app_updater.dart';

final _service = NativeUpdateService();

Future<void> checkAndUpdate() async {
  final result = await _service.checkForUpdate();
  if (!result.updateAvailable) return;

  if (Platform.isAndroid) {
    if (result.immediateAllowed) {
      await _service.startImmediateUpdate();
    } else if (result.flexibleAllowed) {
      _service.installStateStream().listen((event) {
        final status = _service.statusFromString(event['status'] as String?);
        if (status == InstallStatus.downloaded) {
          _service.completeFlexibleUpdate();
        }
      });
      await _service.startFlexibleUpdate();
    }
  } else if (Platform.isIOS) {
    await _service.openStore();
  }
}
```

## Platform behavior differences

| | Android | iOS |
|---|---|---|
| Data source | Google Play Store (via Play Core) | Public iTunes Lookup API |
| Update mechanism | In-app: immediate (blocking) or flexible (background) | Opens App Store listing; Apple provides no in-app self-update API |
| Requires store install to test | Yes (Play Store track) | Yes (App Store release) |
| `immediateAllowed` / `flexibleAllowed` | populated | always `false` |
| `currentVersion` / `latestVersion` | not populated | populated |
| Progress events | `installStateStream()` | not applicable |

## Known limitations

- **iOS storefront**: `checkForUpdate()` queries the iTunes Lookup API
  without a `country` parameter, so it effectively checks the **US** App
  Store listing. If your app is region-locked and not available in the US
  store, the lookup can fail even though the app is live elsewhere.
- **Resuming an already-downloaded Android flexible update**: if the app is
  killed after a flexible update finishes downloading but before the user
  taps **Restart**, the next `checkForUpdate()` will still report
  `updateAvailable: true` / `flexibleAllowed: true`. Calling
  `startFlexibleUpdate()` again in that state is unnecessary — call
  `completeFlexibleUpdate()` directly instead if you want to handle that
  case explicitly.
- Version comparison on iOS is done with numeric string comparison
  (`NSString.compare(_:options:.numeric)`), which works for standard
  dotted-numeric versions (`1.2.3`, `1.10.0`, ...) but not arbitrary
  pre-release suffixes (`1.2.0-beta`).

## Troubleshooting

- **"updateAvailable: false" always, even though a newer version is live
  (Android)** — you're almost certainly running a debug/local build. Play
  Core only has data when the running APK/AAB was installed via a Play
  Store distribution channel (including internal testing tracks).
- **`PARSE_FAILED` (iOS)** — either the app has never been submitted to the
  App Store under this bundle ID, or it isn't available in the US
  storefront (see [Known limitations](#known-limitations)).
- **`NO_ACTIVITY` (Android)** — the method was invoked before the Flutter
  engine finished attaching to an `Activity`. This resolves itself; avoid
  calling `checkForUpdate()` synchronously in top-level `main()`.
- **Flexible update snackbar never appears** — confirm you're listening to
  `installStateStream()` *before* calling `startFlexibleUpdate()` (as
  `UpdateChecker` does internally), otherwise you can miss the
  `downloaded` event that fires shortly after the download completes.

## Example app

See [`example/`](example) for a runnable app demonstrating both patterns:

- `HomePage` ([`main.dart`](example/lib/main.dart)) — the automatic
  `UpdateChecker` flow wrapped around the home screen, plus a button that
  calls `checkForUpdate()` directly and prints the raw result.
- `ManualUpdateFlowPage`
  ([`manual_update_flow_page.dart`](example/lib/manual_update_flow_page.dart))
  — the fully manual pattern (custom dialog, Android immediate/flexible
  branching, install-state listener, restart snackbar) described in
  [Full manual-flow example](#full-manual-flow-example) above.
