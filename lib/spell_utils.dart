// ابزارهای بررسی املا و پیشنهاد کلمات

/// محاسبه فاصله لونشتاین (برای پیشنهاد کلمات مشابه)
int levenshtein(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> prev = List.generate(s2.length + 1, (i) => i);
  List<int> curr = List.filled(s2.length + 1, 0);

  for (int i = 1; i <= s1.length; i++) {
    curr[0] = i;
    for (int j = 1; j <= s2.length; j++) {
      int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1,      // حذف
        curr[j - 1] + 1,  // درج
        prev[j - 1] + cost, // جایگزینی
      ].reduce((a, b) => a < b ? a : b);
    }
    prev = List.from(curr);
  }
  return prev[s2.length];
}

/// پیدا کردن پیشنهادات از دیکشنری
List<String> findSuggestions(
  String word,
  Set<String> dictionary, {
  int maxDistance = 2,
  int maxSuggestions = 5,
}) {
  if (word.length < 2) return [];

  final candidates = <MapEntry<String, int>>[];

  for (final dictWord in dictionary) {
    // فقط کلمات با طول نزدیک را بررسی کن (بهینه‌سازی)
    if ((dictWord.length - word.length).abs() > maxDistance) continue;

    final dist = levenshtein(word, dictWord);
    if (dist > 0 && dist <= maxDistance) {
      candidates.add(MapEntry(dictWord, dist));
    }
  }

  candidates.sort((a, b) => a.value.compareTo(b.value));
  return candidates.take(maxSuggestions).map((e) => e.key).toList();
}

/// نرمال‌سازی متن فارسی/کردی
String normalizePersianKurdish(String text) {
  return text
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('إ', 'ا')
      .replaceAll('أ', 'ا')
      .replaceAll('ۀ', 'ه')
      .replaceAll(RegExp(r'\u200c{2,}'), '\u200c') // نیم‌فاصله تکراری
      .replaceAll(RegExp(r' +'), ' ')
      .trim();
}
