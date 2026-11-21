package io.nexadrive.foreground;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

/** One ongoing notification for all active NexaDrive transfers. */
public final class TransferForegroundService extends Service {
    private static final String TAG = "NexaTransferFgs";
    private static final String CHANNEL_ID = "nexadrive_transfers";
    private static final int NOTIFICATION_ID = 0x4e46;

    static final String ACTION_START = "io.nexadrive.foreground.START";
    static final String ACTION_UPDATE = "io.nexadrive.foreground.UPDATE";
    static final String ACTION_STOP = "io.nexadrive.foreground.STOP";
    static final String EXTRA_TEXT = "io.nexadrive.foreground.TEXT";

    static void start(Context context, String text) {
        send(context, ACTION_START, text, true);
    }

    static void update(Context context, String text) {
        send(context, ACTION_UPDATE, text, true);
    }

    static void stop(Context context) {
        send(context, ACTION_STOP, null, false);
    }

    private static void send(Context context, String action, String text, boolean foregroundStart) {
        try {
            Intent intent = new Intent(context, TransferForegroundService.class)
                    .setAction(action)
                    .putExtra(EXTRA_TEXT, text);
            if (foregroundStart && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (Exception error) {
            // A background-start restriction must never fail the transfer that
            // asked for the notification. The ledger will retry while work is
            // active and will ask for a stop again when it goes idle.
            Log.w(TAG, "Could not update the transfer notification", error);
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            return START_NOT_STICKY;
        }
        String text = intent == null ? null : intent.getStringExtra(EXTRA_TEXT);
        showNotification(text == null || text.isEmpty() ? "Transferring files" : text);
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Transfers", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Ongoing uploads, downloads and folder sync");
        manager.createNotificationChannel(channel);
    }

    @SuppressWarnings("deprecation")
    private void showNotification(String text) {
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        PendingIntent launch = launchIntent();
        builder
                .setSmallIcon(R.drawable.ic_stat_transfer)
                .setContentTitle("NexaDrive transfers")
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setPriority(Notification.PRIORITY_LOW)
                .setColor(Color.rgb(0x35, 0x5C, 0x46))
                .setContentIntent(launch);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setColorized(true);
        }
        Notification notification = builder.build();
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
            } else {
                startForeground(NOTIFICATION_ID, notification);
            }
        } catch (Exception error) {
            // Keep the notification visible with a compatible type if an OEM
            // rejects the typed start; the manifest still declares dataSync.
            Log.w(TAG, "Typed foreground start failed", error);
            try {
                startForeground(NOTIFICATION_ID, notification);
            } catch (Exception fallbackError) {
                Log.w(TAG, "Foreground start failed", fallbackError);
            }
        }
    }

    private PendingIntent launchIntent() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch == null) launch = new Intent(Intent.ACTION_MAIN);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getActivity(this, 0, launch, flags);
    }
}
