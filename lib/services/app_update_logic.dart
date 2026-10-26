/// Positive when [remote] is a newer version name than [local].
int compareVersionNames(String remote, String local) {
  final a = _versionParts(remote);
  final b = _versionParts(local);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

/// [remoteBuild] is only used when the version names are equal.
/// Null or a number below 1 means "this file has no build number".
bool isRemoteNewer({
  required String localVersion,
  required int localBuild,
  required String remoteVersion,
  required int? remoteBuild,
}) {
  final nameCompare = compareVersionNames(remoteVersion, localVersion);
  if (nameCompare > 0) return true;
  if (nameCompare < 0) return false;
  if (remoteBuild == null || remoteBuild < 1) return false;
  return remoteBuild > localBuild;
}

class RemoteRelease {
  final String version;
  final int? buildNumber;
  final bool forceUpdate;
  final String downloadUrl;
  final String changelog;

  const RemoteRelease({
    required this.version,
    required this.buildNumber,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.changelog,
  });
}

/// Returns null when the file has no usable https download link.
RemoteRelease? parseRemoteRelease(Map<String, dynamic> json) {
  final version = json['version']?.toString().trim() ?? '';
  final url = (json['download_url'] ?? json['apk_url'] ?? json['apkUrl'])
          ?.toString()
          .trim() ??
      '';
  if (version.isEmpty || !_httpsUrl(url)) return null;
  return RemoteRelease(
    version: version,
    buildNumber: _asBuildNumber(json['build_number'] ?? json['buildNumber']),
    forceUpdate: _asBool(
      json['force_update'] ?? json['force_upload'] ?? json['forceUpdate'],
    ),
    downloadUrl: url,
    changelog: json['changelog']?.toString().trim() ?? '',
  );
}

List<int> _versionParts(String version) {
  final core = version.split('+').first.trim();
  if (core.isEmpty) return const [0];
  return core.split('.').map((part) {
    final digits = RegExp(r'^\d+').stringMatch(part.trim());
    return int.tryParse(digits ?? '') ?? 0;
  }).toList();
}

int? _asBuildNumber(Object? value) {
  if (value == null) return null;
  final parsed = value is num ? value.toInt() : int.tryParse(value.toString());
  if (parsed == null || parsed < 1) return null;
  return parsed;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }
  return false;
}

bool _httpsUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}
