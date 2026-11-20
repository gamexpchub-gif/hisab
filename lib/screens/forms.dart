import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/theme.dart';

/// Labelled text field with bottom spacing.
Widget field(TextEditingController c, String label,
    {bool number = false, int maxLines = 1, ValueChanged<String>? onChanged, String? hint}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      maxLines: maxLines,
      onChanged: onChanged,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

/// Date selector showing dd Mon yyyy, holding a yyyy-MM-dd value.
class DateField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(value) ?? DateTime.now(),
            firstDate: DateTime(2015),
            lastDate: DateTime.now().add(const Duration(days: 366)),
          );
          if (picked != null) onChanged(ymd(picked));
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.event_rounded)),
          child: Text(prettyDate(value)),
        ),
      ),
    );
  }
}

/// Dropdown of rows (id + name).
class RowPicker extends StatelessWidget {
  final String label;
  final List<Rec> rows;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? noneLabel;
  final String Function(Rec r)? text;
  const RowPicker({
    super.key,
    required this.label,
    required this.rows,
    required this.value,
    required this.onChanged,
    this.noneLabel,
    this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        key: ValueKey('${rows.length}-$value'),
        value: rows.any((r) => asInt(r['id']) == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (noneLabel != null) DropdownMenuItem<int?>(value: null, child: Text(noneLabel!)),
          for (final r in rows)
            DropdownMenuItem<int?>(
              value: asInt(r['id']),
              child: Text(text != null ? text!(r) : r['name'] as String, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Section heading used inside forms.
class FormHeading extends StatelessWidget {
  final String text;
  const FormHeading(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: C.ink)),
      );
}
