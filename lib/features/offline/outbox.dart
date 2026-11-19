import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';

/// Действие, которое не удалось отправить без сети. Хранится на устройстве и уходит
/// на сервер, как только сеть появится (на месте квеста часто нет связи).
@immutable
class OutboxItem {
  const OutboxItem({required this.id, required this.type, required this.ref, required this.at, this.payload = const {}});
  final String id, type, ref; // type: checkin | message; ref: questId / chatId
  final DateTime at;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {'id': id, 'type': type, 'ref': ref, 'at': at.toIso8601String(), 'payload': payload};
  static OutboxItem fromJson(Map<String, Object?> j) =>
      OutboxItem(id: j['id']! as String, type: j['type']! as String, ref: j['ref']! as String, at: DateTime.parse(j['at']! as String), payload: (j['payload'] as Map?)?.cast<String, Object?>() ?? const {});
}

class OutboxController extends Notifier<List<OutboxItem>> {
  static const _k = 'outbox';

  @override
  List<OutboxItem> build() {
    final raw = ref.watch(prefsProvider).getString(_k);
    if (raw == null) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) OutboxItem.fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() => ref.read(prefsProvider).setString(_k, jsonEncode([for (final i in state) i.toJson()]));

  Future<void> add(OutboxItem i) async {
    state = [...state.where((x) => x.id != i.id), i];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((x) => x.id != id).toList();
    await _save();
  }

  bool hasCheckIn(String questId) => state.any((x) => x.type == 'checkin' && x.ref == questId);
}

final outboxProvider = NotifierProvider<OutboxController, List<OutboxItem>>(OutboxController.new);
