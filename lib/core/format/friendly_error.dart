/// Converts common technical exceptions into short Indonesian messages.
String friendlyError(Object error) {
  String text;
  if (error is ArgumentError) {
    text = error.message?.toString() ?? error.toString();
  } else if (error is StateError) {
    text = error.message;
  } else if (error is FormatException) {
    text = error.message;
  } else {
    text = error.toString();
  }
  for (final prefix in const [
    'Bad state: ',
    'Invalid argument(s): ',
    'Exception: ',
    'FormatException: ',
    'StateError: ',
    'ArgumentError: ',
  ]) {
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
  }
  final lower = text.toLowerCase();
  if (lower.contains('sqlite') ||
      lower.contains('databaseexception') ||
      lower.contains('database_closed')) {
    return 'Data gagal disimpan atau dibaca. Coba lagi. Jika terus terjadi, buat backup lalu mulai ulang aplikasi.';
  }
  if (lower.contains('permission')) {
    return 'Izin belum diberikan. Buka Pengaturan aplikasi di HP lalu izinkan akses yang diminta.';
  }
  if (lower.contains('missingpluginexception') ||
      lower.contains('platformexception')) {
    return 'Fitur ini tidak tersedia di perangkat atau belum siap. Mulai ulang aplikasi lalu coba lagi.';
  }
  text = text.trim();
  return text.isEmpty ? 'Terjadi kesalahan. Silakan coba lagi.' : text;
}
