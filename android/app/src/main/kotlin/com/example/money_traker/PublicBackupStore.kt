package com.example.money_traker

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.util.Calendar

/**
 * Writes the daily backup into the public Downloads/MoneyTracker folder.
 * Those files stay on the phone if the app is uninstalled. The caller runs
 * this while the app is open. Nothing is scheduled in the background.
 */
object PublicBackupStore {
    private const val FOLDER = "MoneyTracker"
    private const val retiredKeepDays = 3
    private val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER/"
    private val datedName = Regex("""money_traker_(\d{4})-(\d{2})-(\d{2})(?: \(\d+\))?\.json""")
    private val retiredName = Regex(
        """money_traker_(\d{4}-\d{2}-\d{2})_old_(\d{4})-(\d{2})-(\d{2})(?: \(\d+\))?\.json""",
    )

    fun save(context: Context, sourcePath: String, displayName: String, keepDays: Int): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("Phone folder backup needs Android 10 or newer")
        }
        val bytes = File(sourcePath).readBytes()
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI

        deleteOwned(context, displayName)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create $relativePath$displayName")

        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not write $displayName")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        resolver.update(
            uri,
            ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
            null,
            null,
        )
        prune(context, keepDays)
        pruneRetired(context)
        return relativePath + displayName
    }

    // Keeps the previous copies for 3 days under a name the restore scan ignores.
    fun retireActive(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        pruneRetired(context)
        val today = todayStamp()
        for (name in activeNames(context)) {
            val match = datedName.matchEntire(name) ?: continue
            val original = "${match.groupValues[1]}-${match.groupValues[2]}-${match.groupValues[3]}"
            val target = uniqueName(context, "money_traker_${original}_old_$today.json")
            renameBackup(context, name, target)
        }
    }

    private fun prune(context: Context, keepDays: Int) {
        val days = keepDays.coerceAtLeast(1)
        val cutoff = stampDaysAgo(days - 1)
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        resolver.query(
            collection,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
            arrayOf("money_traker_%.json"),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameCol) ?: continue
                if (pathCol >= 0) {
                    val path = cursor.getString(pathCol) ?: ""
                    if (path.isNotEmpty() && !path.contains(FOLDER)) continue
                }
                val match = datedName.matchEntire(name) ?: continue
                val stamp = match.groupValues[1].toInt() * 10000 +
                    match.groupValues[2].toInt() * 100 +
                    match.groupValues[3].toInt()
                if (stamp < cutoff) {
                    val uri = ContentUris.withAppendedId(collection, cursor.getLong(idCol))
                    resolver.delete(uri, null, null)
                }
            }
        }
    }

    private fun deleteOwned(context: Context, displayName: String) {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        resolver.query(
            collection,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(displayName),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                if (pathCol >= 0) {
                    val path = cursor.getString(pathCol) ?: ""
                    if (path.isNotEmpty() && !path.contains(FOLDER)) continue
                }
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(idCol))
                try {
                    resolver.delete(uri, null, null)
                } catch (_: SecurityException) {
                }
            }
        }
        val direct = File(publicDir(), displayName)
        if (direct.isFile) {
            try {
                direct.delete()
            } catch (_: SecurityException) {
            }
        }
    }

    private fun stampDaysAgo(days: Int): Int {
        val calendar = Calendar.getInstance()
        calendar.add(Calendar.DAY_OF_YEAR, -days)
        return calendar.get(Calendar.YEAR) * 10000 +
            (calendar.get(Calendar.MONTH) + 1) * 100 +
            calendar.get(Calendar.DAY_OF_MONTH)
    }

    fun publicDir(): File {
        return File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            FOLDER,
        )
    }

    /// True only when this install can see files left by a previous install.
    /// An empty directory listing is not enough: after reinstall those files
    /// stay on disk but stay hidden until all-files access is granted.
    fun folderReadable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        return hasReadStorage(context)
    }

    fun scan(context: Context): Map<String, Any> {
        try {
            pruneRetired(context)
        } catch (_: Exception) {
        }
        val merged = linkedMapOf<String, Long>()
        listFromDisk()?.let { found ->
            for ((name, modified) in found) merged[name] = modified
        }
        for ((name, modified) in listFromMediaStore(context)) {
            val current = merged[name]
            if (current == null || modified > current) merged[name] = modified
        }
        val files = merged.map { (name, modified) ->
            mapOf("name" to name, "modified" to modified)
        }
        return mapOf(
            "readable" to folderReadable(context),
            "files" to files,
        )
    }

    fun stage(context: Context, displayName: String): String {
        if (!datedName.matches(displayName)) {
            throw IllegalArgumentException("Unexpected backup name")
        }
        val cache = File(context.cacheDir, "restore_$displayName")
        val direct = File(publicDir(), displayName)
        if (direct.isFile && direct.canRead()) {
            direct.copyTo(cache, overwrite = true)
            return cache.absolutePath
        }
        val uri = findDownloadUri(context, displayName)
            ?: throw IllegalStateException("Backup file not found")
        context.contentResolver.openInputStream(uri)?.use { input ->
            cache.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Could not read backup")
        return cache.absolutePath
    }

    private fun hasReadStorage(context: Context): Boolean {
        return context.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun listFromDisk(): List<Pair<String, Long>>? {
        val listed = try {
            publicDir().listFiles()
        } catch (_: SecurityException) {
            null
        } ?: return null
        return listed.mapNotNull { file ->
            if (!file.isFile || !datedName.matches(file.name)) return@mapNotNull null
            file.name to file.lastModified()
        }
    }

    private fun listFromMediaStore(context: Context): List<Pair<String, Long>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val result = mutableListOf<Pair<String, Long>>()
        val projection = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
            arrayOf("money_traker_%.json"),
            null,
        )?.use { cursor ->
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val modifiedCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameCol) ?: continue
                if (!datedName.matches(name)) continue
                if (pathCol >= 0) {
                    val path = cursor.getString(pathCol) ?: ""
                    if (path.isNotEmpty() && !path.contains(FOLDER)) continue
                }
                val modified = if (modifiedCol >= 0) cursor.getLong(modifiedCol) * 1000 else 0L
                result.add(name to modified)
            }
        }
        return result
    }

    private fun findDownloadUri(context: Context, displayName: String): android.net.Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(displayName),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                if (pathCol >= 0) {
                    val path = cursor.getString(pathCol) ?: ""
                    if (path.isNotEmpty() && !path.contains(FOLDER)) continue
                }
                return ContentUris.withAppendedId(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    cursor.getLong(idCol),
                )
            }
        }
        return null
    }

    private fun pruneRetired(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val cutoff = stampDaysAgo(retiredKeepDays)
        for (name in retiredNames(context)) {
            val match = retiredName.matchEntire(name) ?: continue
            val stamp = match.groupValues[2].toInt() * 10000 +
                match.groupValues[3].toInt() * 100 +
                match.groupValues[4].toInt()
            if (stamp <= cutoff) deleteOwned(context, name)
        }
    }

    private fun activeNames(context: Context): List<String> {
        val names = linkedSetOf<String>()
        listFromDisk()?.forEach { (name, _) -> names.add(name) }
        listFromMediaStore(context).forEach { (name, _) -> names.add(name) }
        return names.toList()
    }

    private fun retiredNames(context: Context): List<String> {
        val names = linkedSetOf<String>()
        val listed = try {
            publicDir().listFiles()
        } catch (_: SecurityException) {
            null
        }
        if (listed != null) {
            for (file in listed) {
                if (file.isFile && retiredName.matches(file.name)) names.add(file.name)
            }
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return names.toList()
        val projection = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
            arrayOf("money_traker_%_old_%.json"),
            null,
        )?.use { cursor ->
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameCol) ?: continue
                if (!retiredName.matches(name)) continue
                if (pathCol >= 0) {
                    val path = cursor.getString(pathCol) ?: ""
                    if (path.isNotEmpty() && !path.contains(FOLDER)) continue
                }
                names.add(name)
            }
        }
        return names.toList()
    }

    private fun uniqueName(context: Context, desired: String): String {
        if (!nameExists(context, desired)) return desired
        val dot = desired.lastIndexOf('.')
        val stem = if (dot >= 0) desired.substring(0, dot) else desired
        val ext = if (dot >= 0) desired.substring(dot) else ""
        var index = 1
        while (index < 50) {
            val candidate = "$stem ($index)$ext"
            if (!nameExists(context, candidate)) return candidate
            index++
        }
        return "$stem ($index)$ext"
    }

    private fun nameExists(context: Context, displayName: String): Boolean {
        val direct = File(publicDir(), displayName)
        if (direct.isFile) return true
        return findDownloadUri(context, displayName) != null
    }

    private fun renameBackup(context: Context, from: String, to: String) {
        if (from == to) return
        val bytes = readBytes(context, from) ?: return
        val wrote = writeDisplayName(context, to, bytes) || writeDirect(to, bytes)
        if (!wrote) return
        deleteOwned(context, from)
    }

    private fun writeDirect(displayName: String, bytes: ByteArray): Boolean {
        return try {
            val dest = File(publicDir(), displayName)
            if (dest.isFile && dest.length() == bytes.size.toLong()) return true
            dest.parentFile?.mkdirs()
            dest.writeBytes(bytes)
            dest.isFile
        } catch (_: Exception) {
            false
        }
    }

    private fun readBytes(context: Context, displayName: String): ByteArray? {
        val direct = File(publicDir(), displayName)
        if (direct.isFile && direct.canRead()) {
            try {
                return direct.readBytes()
            } catch (_: Exception) {
            }
        }
        val uri = findDownloadUri(context, displayName) ?: return null
        return try {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun writeDisplayName(context: Context, displayName: String, bytes: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not write $displayName")
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            true
        } catch (_: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }

    private fun todayStamp(): String {
        val calendar = Calendar.getInstance()
        return "%04d-%02d-%02d".format(
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
        )
    }
}
