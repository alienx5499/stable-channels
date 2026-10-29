package com.stablechannels.app.domain.update

/** When the Home card offers an update from Google Play. */
object UpdateBanner {
    /**
     * Shows when Play has a newer version code than the one installed, unless the user dismissed
     * that version or a newer one. No available version never shows the card.
     */
    fun shouldShow(
        availableVersionCode: Int?,
        installedVersionCode: Int,
        dismissedVersionCode: Int?,
    ): Boolean {
        if (availableVersionCode == null || availableVersionCode <= installedVersionCode)
            return false
        return dismissedVersionCode == null || availableVersionCode > dismissedVersionCode
    }
}
