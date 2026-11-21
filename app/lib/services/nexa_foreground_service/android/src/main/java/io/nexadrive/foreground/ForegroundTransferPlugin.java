package io.nexadrive.foreground;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Registers the transfer notification channel on every Flutter engine.
 *
 * WorkManager starts its own engine after process death, so a handler attached
 * only to MainActivity would be unreachable from the resumed transfer queues.
 */
public final class ForegroundTransferPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private static final String CHANNEL = "nexadrive/foreground_transfer";
    private static final int NOTIFICATION_PERMISSION_REQUEST = 0x4e46;

    private Context applicationContext;
    private MethodChannel channel;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPermissionResult;

    private final PluginRegistry.RequestPermissionsResultListener permissionListener =
            (requestCode, permissions, grantResults) -> {
                if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false;
                MethodChannel.Result pending = pendingPermissionResult;
                pendingPermissionResult = null;
                boolean granted = grantResults.length > 0
                        && grantResults[0] == PackageManager.PERMISSION_GRANTED;
                if (pending != null) pending.success(granted);
                return true;
            };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (applicationContext == null) {
            result.error("unavailable", "No Android context", null);
            return;
        }
        try {
            switch (call.method) {
                case "start":
                    TransferForegroundService.start(applicationContext, textOf(call));
                    result.success(null);
                    break;
                case "update":
                    TransferForegroundService.update(applicationContext, textOf(call));
                    result.success(null);
                    break;
                case "stop":
                    TransferForegroundService.stop(applicationContext);
                    result.success(null);
                    break;
                case "notificationsEnabled":
                    result.success(notificationsEnabled());
                    break;
                case "requestNotificationPermission":
                    requestNotificationPermission(result);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception error) {
            // A notification/channel failure must never fail a transfer.
            result.success(false);
        }
    }

    private static String textOf(MethodCall call) {
        String text = call.argument("text");
        return text == null || text.isEmpty() ? "Transferring files" : text;
    }

    private boolean notificationsEnabled() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                        != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager manager =
                (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
        return manager == null || manager.areNotificationsEnabled();
    }

    /**
     * Asks only when an Activity is present. No "prompted" flag is written
     * before the result: a denial stays retryable on a later transfer.
     */
    private void requestNotificationPermission(MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true);
            return;
        }
        if (applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }
        final Activity host = activity;
        if (host == null || host.isFinishing() || host.isDestroyed()) {
            // Background engine: no Activity, so no prompt is possible.
            result.success(false);
            return;
        }
        MethodChannel.Result previous = pendingPermissionResult;
        pendingPermissionResult = result;
        if (previous != null) previous.success(false);
        host.requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(permissionListener);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        ActivityPluginBinding binding = activityBinding;
        activityBinding = null;
        if (binding != null) {
            binding.removeRequestPermissionsResultListener(permissionListener);
        }
        activity = null;
        MethodChannel.Result pending = pendingPermissionResult;
        pendingPermissionResult = null;
        if (pending != null) pending.success(false);
    }
}
