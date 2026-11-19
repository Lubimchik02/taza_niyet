import 'dart:math' as math;

/// Точка на карте.
typedef LatLng = ({double lat, double lng});

/// Расстояние между точками по формуле гаверсинусов, км.
double distanceKm(LatLng a, LatLng b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// «0,8», «12» — с запятой для ru/kk.
String formatKm(double km, String languageCode) {
  final s = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return languageCode == 'en' ? s : s.replaceAll('.', ',');
}

enum LocationPermission { notAsked, granted, denied }

/// Геолокация. Реальная реализация (пакет geolocator, разрешение «только при использовании») — этап 12.
abstract interface class LocationService {
  LocationPermission get permission;
  Future<LocationPermission> request();
  Future<LatLng?> current();
}

/// Демо: после разрешения — центр Астаны (или [demoPosition], чтобы «встать» на место квеста).
class FakeLocationService implements LocationService {
  LocationPermission _p = LocationPermission.notAsked;

  LatLng? demoPosition;

  @override
  LocationPermission get permission => _p;

  @override
  Future<LocationPermission> request() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _p = LocationPermission.granted;
  }

  @override
  Future<LatLng?> current() async => _p == LocationPermission.granted ? demoPosition ?? (lat: 51.1282, lng: 71.4306) : null;
}
