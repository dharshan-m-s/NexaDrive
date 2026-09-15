import 'dart:async';

import 'package:flutter/services.dart';

import 'update_manifest.dart';

/// Hand-rolled platform channel to the Android host side (`MainActivity`).
///
/// Kept separate from the rest of the update stack so tests never touch the
/// messenger and to keep the channel method surface explicit.
class UpdaterMethodChannel {
  static const MethodChannel _channel = MethodChannel('nexadrive/updater');

  /// The device ABIs reported by `Build.SUPPORTED_ABIS` (primary first).
  Future<List<String>?> resolveAbi() async {
    try {
      final value = await _channel
          .invokeMethod<String>('currentAbi')
          .timeout(const Duration(seconds: 5));
      return value == null ? const [] : [value];
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Hands a verified APK to the system installer. True only when the system
  /// package installer was actually launched; the user still confirms.
  Future<bool> installApk(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'path': path,
      });
      return result ?? false;
    } on MissingPluginException {
      throw const UpdateException(
        UpdateErrorKind.installFailed,
        'The app installer is unavailable on this device.',
      );
    } on PlatformException {
      throw const UpdateException(
        UpdateErrorKind.installFailed,
        'Android could not start the package installer.',
      );
    }
  }

  /// Opens "Install unknown apps" for this package when the system blocks APK
  /// sideloading for the app.
  Future<void> openUnknownSourceSettings() async {
    try {
      await _channel.invokeMethod<void>('openUnknownSourceSettings');
    } on MissingPluginException {
      // Non-Android platform; nothing to do.
    } on PlatformException {
      // The OEM has no such screen; the installer dialog reports it.
    }
  }

  /// Opens this app's settings detail page (used to guide the user to grant
  /// authorization or manage storage).
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      // Non-Android platform; nothing to do.
    } on PlatformException {
      // No detail screen available.
    }
  }
}