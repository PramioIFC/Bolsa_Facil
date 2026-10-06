import 'package:flutter/material.dart';

import '../models/stock.dart';
import '../theme.dart';
import '../utils/format.dart';

class StockTile extends StatelessWidget {
  const StockTile({
    super.key,
    required this.stock,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  final Stock stock;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final up = stock.changePercent >= 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _Logo(stock: stock),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stock.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 4),
                Text(stock.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(stock.price), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 4),
              Text(formatPercent(stock.changePercent), style: TextStyle(color: up ? positive : negative, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(width: 6),
            IconButton(
              tooltip: isFavorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
              onPressed: onFavorite,
              icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded, color: isFavorite ? const Color(0xFFFFB020) : Colors.blueGrey.shade300),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.stock});
  final Stock stock;

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        width: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFF0EFFF), borderRadius: BorderRadius.circular(14)),
        child: stock.logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(stock.logoUrl!, width: 34, height: 34, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _letters()),
              )
            : _letters(),
      );

  Widget _letters() {
    final end = stock.symbol.length < 2 ? stock.symbol.length : 2;
    return Text(
      stock.symbol.substring(0, end),
      style: const TextStyle(color: primary, fontWeight: FontWeight.w900),
    );
  }
}

/// Atalho usado pelas telas para formatar valores em reais (pt-BR).
String money(double value) => formatMoney(value);
