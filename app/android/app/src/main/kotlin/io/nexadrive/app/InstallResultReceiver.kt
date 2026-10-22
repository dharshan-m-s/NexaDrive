package io.nexadrive.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/// Receives the status of an APK install session committed by [MainActivity].
///
/// When a normal (non-privileged) app commits a [PackageInstaller] session,
/// Android does **not** show the confirmation dialog on its own. Instead it
/// delivers `STATUS_PENDING_USER_ACTION` to this receiver together with the
/// dialog intent in `Intent.EXTRA_INTENT`; the app is required to launch that
/// intent. Without this step the session sits forever and the user never sees
/// the "install this update?" prompt.
///
/// `STATUS_SUCCESS` / `STATUS_FAILURE*` need no action here: the Update
/// Center reconciles the installed version when the app is next resumed.
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) return

        val confirm = confirmIntent(intent) ?: return
        // Launched from a receiver, so the system dialog needs its own task.
        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(confirm)
        } catch (_: Exception) {
            // An OEM build without the install-confirmation activity; the
            // strict-mode installer will surface the block itself.
        }
    }

    private fun confirmIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
}
