class SmsHash {
  static String of({
    required String smsId,
    required String sender,
    required String body,
  }) {
    final input = '$smsId\n${sender.trim()}\n${body.trim()}';
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
