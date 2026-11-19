import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Короткий доступ к строкам: `context.l.tabHome`.
extension L10nX on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}
