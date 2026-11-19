import 'package:flutter/widgets.dart';

import '../../../core/l10n_x.dart';

/// «3 ч», «2,5 ч» (en — «2.5 h»).
String formatHours(BuildContext context, double h) {
  final lang = Localizations.localeOf(context).languageCode;
  var s = h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
  if (lang != 'en') s = s.replaceAll('.', ',');
  return context.l.hoursStr(s);
}
