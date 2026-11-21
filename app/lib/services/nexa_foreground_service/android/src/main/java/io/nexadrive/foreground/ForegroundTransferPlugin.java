package io.nexadrive.foreground;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Registers the transfer notification channel on every Flutter engine.
 *
 * WorkManager starts its own engine after process death, so a handler attached
 * only to MainActivity would be unreachable from the resumed upload queue.
 */
public final class ForegroundTransferPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private static final String CHANNEL = "nexadrive/foreground_transfer";
    private static final String PREFS = "nexadrive_foreground_transfer";
    private static final String PERMISSION_PROMPTED = "notification_permission_prompted";
    private static final int NOTIFICATION_PERMISSION_REQUEST = 0x4e46;

    private Context applicationContext;
    private MethodChannel channel;
    private Activity activity;

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
        switch (call.method) {
            case "start":
                requestNotificationPermissionOnce();
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
            default:
                result.notImplemented();
        }
    }

    private static String textOf(MethodCall call) {
        String text = call.argument("text");
        return text == null || text.isEmpty() ? "Transferring files" : text;
    }

    /** Android 13+: ask once, in the foreground, when real work begins. */
    private void requestNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return;
        final Activity host = activity;
        if (host == null || host.isFinishing() || host.isDestroyed()) return;
        SharedPreferences prefs =
                host.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (prefs.getBoolean(PERMISSION_PROMPTED, false)) return;
        if (host.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) return;
        prefs.edit().putBoolean(PERMISSION_PROMPTED, true).apply();
        host.requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }
}
