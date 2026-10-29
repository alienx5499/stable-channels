package com.stablechannels.app.domain.update

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateBannerTest {
    @Test
    fun showsWhenPlayHasNewer() {
        assertTrue(
            UpdateBanner.shouldShow(
                availableVersionCode = 11,
                installedVersionCode = 10,
                dismissedVersionCode = null,
            )
        )
    }

    @Test
    fun hidesWhenNoUpdate() {
        assertFalse(
            UpdateBanner.shouldShow(
                availableVersionCode = null,
                installedVersionCode = 10,
                dismissedVersionCode = null,
            )
        )
        assertFalse(
            UpdateBanner.shouldShow(
                availableVersionCode = 10,
                installedVersionCode = 10,
                dismissedVersionCode = null,
            )
        )
    }

    @Test
    fun testDismissedVersionHides() {
        assertFalse(
            UpdateBanner.shouldShow(
                availableVersionCode = 11,
                installedVersionCode = 10,
                dismissedVersionCode = 11,
            )
        )
    }

    @Test
    fun testNewerThanDismissedShows() {
        assertTrue(
            UpdateBanner.shouldShow(
                availableVersionCode = 12,
                installedVersionCode = 10,
                dismissedVersionCode = 11,
            )
        )
    }
}
