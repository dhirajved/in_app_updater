import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'native_update_service.dart';

/// Builds an update dialog; [onUpdate] starts the platform update flow
/// (Play Core immediate/flexible on Android, the App Store on iOS),
/// [onLater] dismisses the dialog.
typedef UpdateDialogBuilder =
    Widget Function(
      BuildContext context,
      UpdateCheckResult result,
      VoidCallback onUpdate,
      VoidCallback onLater,
    );

/// Builds the Android "restart to install" [SnackBar]; [onRestart] completes the update.
typedef AndroidRestartSnackBarBuilder =
    SnackBar Function(BuildContext context, VoidCallback onRestart);

/// Wraps your home screen to show Groww-style update prompts: an update
/// dialog first, then Play Core's immediate/flexible flow on Android or the
/// App Store sheet on iOS once the user taps Update. Pass
/// [androidUpdateDialogBuilder]/[iosUpdateDialogBuilder]/
/// [androidRestartSnackBarBuilder] to replace the default UI, or leave unset
/// to use the built-in dialog/snackbar.
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({
    super.key,
    required this.child,
    this.iosUpdateDialogBuilder,
    this.androidUpdateDialogBuilder,
    this.androidRestartSnackBarBuilder,
  });

  final Widget child;
  final UpdateDialogBuilder? iosUpdateDialogBuilder;
  final UpdateDialogBuilder? androidUpdateDialogBuilder;
  final AndroidRestartSnackBarBuilder? androidRestartSnackBarBuilder;

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  final _updateService = NativeUpdateService();
  StreamSubscription<Map<String, dynamic>>? _installStateSub;
  bool _flexibleUpdateInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _installStateSub?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final UpdateCheckResult result;
    try {
      result = await _updateService.checkForUpdate();
    } catch (_) {
      return; // e.g. no network, or not installed from a store build.
    }
    if (!result.updateAvailable || !mounted) return;

    if (Platform.isAndroid) {
      await _showAndroidUpdateDialog(result);
    } else if (Platform.isIOS) {
      await _showIosUpdateDialog(result);
    }
  }

  // ── Android: Play Core immediate/flexible update flow ────────────────────

  Future<void> _showAndroidUpdateDialog(UpdateCheckResult result) {
    if (!result.immediateAllowed && !result.flexibleAllowed) {
      return Future.value();
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var dismissed = false;
        void dismiss() {
          if (dismissed) return;
          dismissed = true;
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        }

        void onUpdate() {
          dismiss();
          _startAndroidUpdateFlow(result);
        }

        void onLater() => dismiss();

        final builder = widget.androidUpdateDialogBuilder;
        if (builder != null) {
          return builder(dialogContext, result, onUpdate, onLater);
        }

        return AlertDialog(
          title: const Text('Update available'),
          content: const Text(
            'A new version of the app is available on the Play Store.',
          ),
          actions: [
            TextButton(onPressed: onLater, child: const Text('Later')),
            FilledButton(onPressed: onUpdate, child: const Text('Update')),
          ],
        );
      },
    );
  }

  Future<void> _startAndroidUpdateFlow(UpdateCheckResult result) async {
    try {
      if (result.immediateAllowed) {
        // High-priority release: block the app until it's updated.
        await _updateService.startImmediateUpdate();
        return;
      }
      if (result.flexibleAllowed && !_flexibleUpdateInFlight) {
        _flexibleUpdateInFlight = true;
        _listenForFlexibleUpdate();
        await _updateService.startFlexibleUpdate();
      }
    } catch (_) {
      // e.g. the user backed out of the Play Core confirmation dialog, or
      // Play Services is unavailable. Reset so a later check can retry.
      _flexibleUpdateInFlight = false;
    }
  }

  void _listenForFlexibleUpdate() {
    _installStateSub = _updateService.installStateStream().listen((event) {
      final status = _updateService.statusFromString(
        event['status'] as String?,
      );
      if (status == InstallStatus.downloaded && mounted) {
        _showRestartSnackBar();
      }
    });
  }

  void _showRestartSnackBar() {
    void onRestart() => _updateService.completeFlexibleUpdate();
    final snackBar =
        widget.androidRestartSnackBarBuilder?.call(context, onRestart) ??
        SnackBar(
          duration: const Duration(days: 1),
          content: const Text('An update just downloaded.'),
          action: SnackBarAction(label: 'RESTART', onPressed: onRestart),
        );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  // ── iOS: App Store lookup + StoreKit sheet ────────────────────────────────

  Future<void> _showIosUpdateDialog(UpdateCheckResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var dismissed = false;
        void dismiss() {
          if (dismissed) return;
          dismissed = true;
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        }

        void onUpdate() {
          dismiss();
          unawaited(_openStore());
        }

        void onLater() => dismiss();

        final builder = widget.iosUpdateDialogBuilder;
        if (builder != null) {
          return builder(dialogContext, result, onUpdate, onLater);
        }

        return AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'A new version (${result.latestVersion}) is available. '
            'You are on ${result.currentVersion}.',
          ),
          actions: [
            TextButton(onPressed: onLater, child: const Text('Later')),
            FilledButton(onPressed: onUpdate, child: const Text('Update')),
          ],
        );
      },
    );
  }

  Future<void> _openStore() async {
    try {
      await _updateService.openStore();
    } catch (_) {
      // Nothing more we can do if StoreKit/UIApplication can't open the listing.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
