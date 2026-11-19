/// Проверки ввода на клиенте. Сервер проверяет всё повторно (этап 12).
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static bool isEmail(String v) => _email.hasMatch(v.trim());

  /// Приводит казахстанский мобильный номер к виду +77XXXXXXXXX.
  /// Принимает 8 7XX…, 7 7XX…, +7 7XX… с пробелами, скобками и дефисами. Иначе — null.
  static String? normalizeKzPhone(String v) {
    var d = v.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.startsWith('+')) d = d.substring(1);
    if (d.length == 11 && (d.startsWith('8') || d.startsWith('7'))) d = d.substring(1);
    if (d.length != 10 || !d.startsWith('7')) return null;
    return '+7$d';
  }

  /// Для показа: +7 777 123 45 67.
  static String formatKzPhone(String e164) {
    final d = e164.substring(2);
    return '+7 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6, 8)} ${d.substring(8)}';
  }

  static bool isName(String v) => RegExp(r'\p{L}.*\p{L}', unicode: true).hasMatch(v.trim());

  /// Возраст по году рождения (без даты — по худшему случаю: день рождения ещё не наступил).
  static int ageFromBirthYear(int year, {DateTime? now}) => (now ?? DateTime.now()).year - year - 1;

  static bool isMinor(int birthYear, {DateTime? now}) => ageFromBirthYear(birthYear, now: now) < 18;

  /// С какого возраста можно пользоваться приложением. Младше 13 — правила магазинов для детских
  /// приложений (Google Play Families, Apple Kids) и согласие родителей; сейчас не поддерживаем.
  /// Сервер проверяет то же самое (миграция 0700).
  static const minAge = 13;

  static bool tooYoung(int birthYear, {DateTime? now}) => ageFromBirthYear(birthYear, now: now) < minAge;
}
