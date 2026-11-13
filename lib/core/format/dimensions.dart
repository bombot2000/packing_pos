/// Formats optional dimensions, or returns null when none were recorded.
String? dimensionsLabel(Object? length, Object? width, Object? height) {
  double n(Object? value) => (value as num?)?.toDouble() ?? 0;
  if (n(length) == 0 && n(width) == 0 && n(height) == 0) return null;
  String part(Object? value) {
    final v = n(value);
    if (v == 0) return '-';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
  return '${part(length)} × ${part(width)} × ${part(height)} cm';
}
