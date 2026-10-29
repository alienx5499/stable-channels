package com.stablechannels.app.services

import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.testing.FakeAppUpdateManager
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AppUpdateCheckerTest {
    private val context = RuntimeEnvironment.getApplication()

    @Test
    fun checkerReturnsVersionWhenAvailable() = runTest {
        val fake = FakeAppUpdateManager(context).apply { setUpdateAvailable(11) }

        assertEquals(11, AppUpdateChecker(fake).availableVersionCode())
    }

    @Test
    fun checkerReturnsNullWhenNoUpdate() = runTest {
        assertNull(AppUpdateChecker(FakeAppUpdateManager(context)).availableVersionCode())
    }

    @Test
    fun checkerReturnsNullWhenPlayFails() = runTest {
        // A sideloaded APK, or a device without Play, fails the request.
        val manager = mock(AppUpdateManager::class.java)
        `when`(manager.appUpdateInfo)
            .thenReturn(Tasks.forException(RuntimeException("Play unavailable")))

        assertNull(AppUpdateChecker(manager).availableVersionCode())
    }
}
