import 'package:intl/intl.dart';

final NumberFormat _currency = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final NumberFormat _decimal2 = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: 2);
final NumberFormat _compact = NumberFormat.compact(locale: 'pt_BR');

/// `1234.5` → `R$ 1.234,50`.
String formatMoney(double value) => _currency.format(value);

/// `1.5` → `+1,50%`; `-0.3` → `-0,30%`.
String formatPercent(double value, {bool signed = true}) {
  final text = '${_decimal2.format(value)}%';
  return signed && value > 0 ? '+$text' : text;
}

/// Número com 2 casas, no padrão brasileiro (`38,52`).
String formatDecimal(double value) => _decimal2.format(value);

/// Valores grandes de forma compacta (`R$ 1,2 bi`), usando o padrão pt-BR.
String formatCompactMoney(double value) => 'R\$ ${_compact.format(value)}';

/// `hoje às 14:32` ou `04/10 às 14:32`.
String formatUpdatedAt(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = time.toLocal();
  final sameDay = local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  final hour = DateFormat('HH:mm').format(local);
  return sameDay ? 'hoje às $hour' : '${DateFormat('dd/MM').format(local)} às $hour';
}
