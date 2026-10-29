package com.stablechannels.app.services

import android.util.Log
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.install.model.UpdateAvailability
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.tasks.await

/**
 * Asks Google Play whether a newer version is available. A sideloaded APK or a device without Play
 * fails the request, which returns null, so the app simply shows no update.
 */
class AppUpdateChecker(private val manager: AppUpdateManager) {
    suspend fun availableVersionCode(): Int? =
        try {
            val info = manager.appUpdateInfo.await()
            if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE)
                info.availableVersionCode()
            else null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Update check failed: ${e.message}")
            null
        }

    private companion object {
        const val TAG = "AppUpdateChecker"
    }
}
