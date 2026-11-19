import '../profile/profile_controller.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../auth/auth_controller.dart';
import '../org/org_controller.dart';
import '../people/people_controller.dart';
import '../profile/data/portfolio.dart';
import '../quests/signups_controller.dart';
import '../shift/shift_controller.dart';

/// Все мои данные одним JSON (право на доступ к своим данным; на сервере — полная выгрузка, этап 12).
Uint8List exportJson(WidgetRef ref) {
  final u = ref.read(sessionProvider);
  final m = ref.read(membershipProvider);
  final data = {
    'exportedAt': DateTime.now().toIso8601String(),
    'profile': {'id': u?.id, 'name': u?.name, 'birthYear': u?.birthYear, 'email': u?.email, 'phone': u?.phone},
    'organization': m == null ? null : {'name': m.orgName, 'status': m.status.name},
    'credits': [
      for (final c in ref.read(creditsProvider))
        {'quest': c.questTitle, 'organization': c.orgName, 'date': c.date.toIso8601String(), 'hours': c.hours, 'tz': c.tz, 'kind': c.kind.name},
    ],
    'signups': [
      for (final s in ref.read(mySignupsProvider))
        {'quest': s.quest.title, 'start': s.start.toIso8601String(), 'status': s.status.name, 'team': s.team?.number, 'shift': s.shift.name, 'hours': s.hours},
    ],
    'friends': ref.read(friendsProvider).friends.toList(),
  };
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
}

/// Портфолио в PDF: подтверждённые часы, организация, QR для проверки.
/// Шрифт Manrope из assets — в стандартных шрифтах PDF нет кириллицы и казахских букв.
Future<Uint8List> exportPortfolioPdf(WidgetRef ref, {required Map<String, String> labels}) async {
  final u = ref.read(sessionProvider);
  final credits = ref.read(creditsProvider).where((c) => c.kind == CreditKind.shift).toList();
  final totals = ref.read(totalsProvider);
  final code = await ref.read(portfolioCodeProvider.future);
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Bold.ttf'));
  const green = PdfColor.fromInt(0xFF3D6B00);
  String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
  String h(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  final doc = pw.Document(title: 'Taza Niyet — ${labels['title']}', author: 'Taza Niyet');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    margin: const pw.EdgeInsets.all(40),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Taza Niyet', style: pw.TextStyle(font: bold, fontSize: 14, color: green)),
            pw.SizedBox(height: 6),
            pw.Text(labels['title']!, style: pw.TextStyle(font: bold, fontSize: 22)),
            pw.SizedBox(height: 4),
            pw.Text(u?.name ?? '', style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 12),
            pw.Text('${labels['hours']}: ${h(totals.hours)}   ·   Tz: ${totals.tz}   ·   ${labels['shifts']}: ${credits.length}', style: const pw.TextStyle(fontSize: 12)),
          ]),
        ),
        pw.Column(children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: portfolioLink(code), width: 96, height: 96),
          pw.SizedBox(height: 4),
          pw.Text(code, style: pw.TextStyle(font: bold, fontSize: 10)),
        ]),
      ]),
      pw.SizedBox(height: 20),
      pw.TableHelper.fromTextArray(
        headers: [labels['date'], labels['quest'], labels['org'], labels['hours'], 'Tz'],
        data: [for (final c in credits) [d(c.date), c.questTitle, c.orgName, h(c.hours), '${c.tz}']],
        headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: green),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 16),
      pw.Text(labels['verify']!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text(portfolioLink(code), style: pw.TextStyle(font: bold, fontSize: 10, color: green)),
      pw.SizedBox(height: 4),
      pw.Text('${labels['issued']} ${d(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ],
  ));
  return doc.save();
}
