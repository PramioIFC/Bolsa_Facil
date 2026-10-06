import 'package:flutter/material.dart';

/// Filtro local separado da busca remota e ordenação da lista visível.
class ListOrderControls<T> extends StatelessWidget {
  const ListOrderControls(
      {super.key,
      required this.order,
      required this.orders,
      required this.onOrderChanged,
      required this.onFilterChanged,
      required this.filterKey});
  final T order;
  final Map<T, String> orders;
  final ValueChanged<T> onOrderChanged;
  final ValueChanged<String> onFilterChanged;
  final Key filterKey;

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
          key: filterKey,
          onChanged: onFilterChanged,
          decoration: const InputDecoration(
            labelText: 'Filtrar lista',
            hintText: 'Código ou nome nesta lista',
            prefixIcon: Icon(Icons.filter_alt_outlined),
          ),
        ),
        const SizedBox(height: 10),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Ordenar por'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: order,
              isExpanded: true,
              onChanged: (value) {
                if (value != null) onOrderChanged(value);
              },
              items: [
                for (final entry in orders.entries)
                  DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis))
              ],
            ),
          ),
        ),
      ]);
}
