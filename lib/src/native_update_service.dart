import 'package:flutter/services.dart';

enum InstallStatus {
  pending,
  downloading,
  downloaded,
  installing,
  installed,
  failed,
  canceled,
  unknown,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.currentVersion,
    this.latestVersion,
  });

  final bool updateAvailable;
  final bool immediateAllowed; // Android only
  final bool flexibleAllowed; // Android only
  final String? currentVersion; // iOS only
  final String? latestVersion; // iOS only
}

/// Bridges to platform-native update checks: Play Core's In-App Update API on
/// Android, an App Store version lookup on iOS. No Flutter update package involved.
class NativeUpdateService {
  static const _methodChannel = MethodChannel('in_app_updater/methods');
  static const _eventChannel = EventChannel('in_app_updater/state');

  Stream<Map<String, dynamic>>? _installStateStream;

  Future<UpdateCheckResult> checkForUpdate() async {
    final map = await _methodChannel.invokeMapMethod<String, dynamic>(
      'checkForUpdate',
    );
    if (map == null) return const UpdateCheckResult(updateAvailable: false);
    return UpdateCheckResult(
      updateAvailable: map['updateAvailable'] as bool? ?? false,
      immediateAllowed: map['immediateAllowed'] as bool? ?? false,
      flexibleAllowed: map['flexibleAllowed'] as bool? ?? false,
      currentVersion: map['currentVersion'] as String?,
      latestVersion: map['latestVersion'] as String?,
    );
  }

  /// Android only: full-screen blocking update flow.
  Future<bool> startImmediateUpdate() async {
    return await _methodChannel.invokeMethod<bool>('startImmediateUpdate') ??
        false;
  }

  /// Android only: background download; call [completeFlexibleUpdate] once downloaded.
  Future<bool> startFlexibleUpdate() async {
    return await _methodChannel.invokeMethod<bool>('startFlexibleUpdate') ??
        false;
  }

  Future<void> completeFlexibleUpdate() {
    return _methodChannel.invokeMethod('completeFlexibleUpdate');
  }

  /// iOS only: opens the App Store listing found by the last [checkForUpdate] call.
  Future<bool> openStore() async {
    return await _methodChannel.invokeMethod<bool>('openStore') ?? false;
  }

  /// Android only: emits Play Core install state while a flexible update downloads.
  Stream<Map<String, dynamic>> installStateStream() {
    _installStateStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event as Map),
    );
    return _installStateStream!;
  }

  InstallStatus statusFromString(String? status) {
    return InstallStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => InstallStatus.unknown,
    );
  }
}
