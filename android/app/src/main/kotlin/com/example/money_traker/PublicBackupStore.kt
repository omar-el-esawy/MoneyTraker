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
    private val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER/"
    private val datedName = Regex("""money_traker_(\d{4})-(\d{2})-(\d{2})(?: \(\d+\))?\.json""")

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
        return relativePath + displayName
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
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        resolver.query(
            collection,
            projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(displayName),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(idCol))
                resolver.delete(uri, null, null)
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

    /// True when this install can see the whole public folder, including files
    /// left behind by a previous install.
    fun folderReadable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            return true
        }
        val listed = try {
            publicDir().listFiles()
        } catch (_: SecurityException) {
            null
        }
        if (listed != null) return true
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 && hasReadStorage(context)) return true
        return false
    }

    fun scan(context: Context): Map<String, Any> {
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
}
