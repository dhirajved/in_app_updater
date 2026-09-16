import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_updater/in_app_updater.dart';

/// Shows how to drive the whole update flow by hand with
/// [NativeUpdateService] — no [UpdateChecker] involved. Use this pattern
/// when you want your own dialog widget, your own state management (bloc,
/// riverpod, ...), or to trigger the check from somewhere other than app
/// launch (e.g. a "Check for updates" button in Settings).
///
/// This mirrors what [UpdateChecker] does internally, so copy it as a
/// starting point rather than re-deriving the flow from scratch:
/// 1. `checkForUpdate()`.
/// 2. Show your own dialog if `updateAvailable` is true.
/// 3. On Android, branch on `immediateAllowed` vs `flexibleAllowed`.
/// 4. For a flexible update, subscribe to `installStateStream()` **before**
///    calling `startFlexibleUpdate()` so the `downloaded` event can't be
///    missed, then prompt the user to `completeFlexibleUpdate()`.
class ManualUpdateFlowPage extends StatefulWidget {
  const ManualUpdateFlowPage({super.key});

  @override
  State<ManualUpdateFlowPage> createState() => _ManualUpdateFlowPageState();
}

class _ManualUpdateFlowPageState extends State<ManualUpdateFlowPage> {
  final _updateService = NativeUpdateService();
  StreamSubscription<Map<String, dynamic>>? _installStateSub;
  bool _flexibleUpdateInFlight = false;
  String _status = 'Idle.';

  @override
  void dispose() {
    _installStateSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAndPrompt() async {
    setState(() => _status = 'Checking…');

    final UpdateCheckResult result;
    try {
      result = await _updateService.checkForUpdate();
    } catch (e) {
      setState(() => _status = 'checkForUpdate failed: $e');
      return;
    }

    if (!result.updateAvailable) {
      setState(() => _status = 'Already up to date.');
      return;
    }
    if (!mounted) return;
    _showCustomUpdateDialog(result);
  }

  /// A hand-rolled dialog instead of UpdateChecker's built-in one — swap in
  /// whatever widget your app's design system uses.
  Future<void> _showCustomUpdateDialog(UpdateCheckResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('A new version is available'),
        content: Text(
          Platform.isIOS
              ? 'Version ${result.latestVersion} is out (you have '
                    '${result.currentVersion}).'
              : 'Update now to get the latest features and fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _startUpdate(result);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _startUpdate(UpdateCheckResult result) async {
    if (Platform.isIOS) {
      setState(() => _status = 'Opening the App Store…');
      try {
        await _updateService.openStore();
      } catch (e) {
        setState(() => _status = 'openStore failed: $e');
      }
      return;
    }

    // Android: pick whichever flow Play Core says is allowed for this
    // rollout — don't assume; a high-priority release may only allow
    // immediateAllowed, a low-priority one may only allow flexibleAllowed.
    try {
      if (result.immediateAllowed) {
        setState(() => _status = 'Starting immediate (blocking) update…');
        // Play Core takes over the UI and restarts the app itself on
        // success, so there's usually nothing left to do after this call.
        await _updateService.startImmediateUpdate();
      } else if (result.flexibleAllowed && !_flexibleUpdateInFlight) {
        _flexibleUpdateInFlight = true;
        // Subscribe BEFORE starting the download so a fast 'downloaded'
        // event can't fire before anyone is listening.
        _listenForFlexibleDownload();
        setState(() => _status = 'Downloading update in the background…');
        await _updateService.startFlexibleUpdate();
      }
    } catch (e) {
      // e.g. the user backed out of the Play Core confirmation dialog.
      _flexibleUpdateInFlight = false;
      setState(() => _status = 'Update flow failed/cancelled: $e');
    }
  }

  void _listenForFlexibleDownload() {
    _installStateSub = _updateService.installStateStream().listen((event) {
      final status = _updateService.statusFromString(
        event['status'] as String?,
      );
      setState(
        () => _status =
            'Install status: ${status.name} '
            '(${event['bytesDownloaded']}/${event['totalBytesToDownload']} bytes)',
      );

      if (status == InstallStatus.downloaded && mounted) {
        _showRestartSnackBar();
      }
    });
  }

  void _showRestartSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: const Text('Update downloaded and ready to install.'),
        action: SnackBarAction(
          label: 'RESTART',
          onPressed: () {
            _updateService.completeFlexibleUpdate();
            _flexibleUpdateInFlight = false;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual update flow')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This screen never touches UpdateChecker — it wires '
              'checkForUpdate(), a custom AlertDialog, the correct Android '
              'immediate/flexible branch, the install-state listener, and '
              'the restart snackbar together by hand. Copy this pattern if '
              'you need the check to run somewhere other than app launch, '
              'or want to plug it into your own state management.',
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAndPrompt,
              child: const Text('Check for update'),
            ),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
