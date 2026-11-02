class SmsHash {
  // Web-only. JavaScript cannot compile the 64-bit literals used on mobile.
  static final BigInt _offset = BigInt.parse('14695981039346656037');
  static final BigInt _prime = BigInt.parse('1099511628211');
  static final BigInt _mask = (BigInt.one << 64) - BigInt.one;
  static final BigInt _sign = BigInt.one << 63;

  static BigInt _signed64(BigInt value) {
    final bits = value & _mask;
    if (bits >= _sign) return bits - (BigInt.one << 64);
    return bits;
  }

  static String of({
    required String smsId,
    required String sender,
    required String body,
  }) {
    final input = '$smsId\n${sender.trim()}\n${body.trim()}';
    var hash = _signed64(_offset);
    for (final unit in input.codeUnits) {
      hash = _signed64((hash ^ BigInt.from(unit)) * _prime);
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
