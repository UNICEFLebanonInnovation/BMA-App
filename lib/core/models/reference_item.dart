import 'dart:convert';

/// One entry of a reference list (nationality, centre, school, round …).
class ReferenceItem {
  const ReferenceItem({
    required this.kind,
    required this.id,
    required this.name,
    this.nameEn,
    this.parentId,
    this.extra = const {},
  });

  final String kind;
  final int id;
  final String name;
  final String? nameEn;
  final int? parentId;
  final Map<String, dynamic> extra;

  String labelFor(String languageCode) {
    if (languageCode == 'ar') return name;
    return (nameEn?.isNotEmpty ?? false) ? nameEn! : name;
  }

  Map<String, Object?> toRow() => {
        'kind': kind,
        'id': id,
        'name': name,
        'name_en': nameEn,
        'parent_id': parentId,
        'data': jsonEncode(extra),
      };

  static ReferenceItem fromRow(Map<String, Object?> row) => ReferenceItem(
        kind: row['kind'] as String,
        id: row['id'] as int,
        name: (row['name'] as String?) ?? '',
        nameEn: row['name_en'] as String?,
        parentId: row['parent_id'] as int?,
        extra: row['data'] == null
            ? const {}
            : Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map),
      );

  /// Build from a bootstrap JSON object. The display name is taken from
  /// `name`, falling back to `material` (grading definitions) or `number`.
  static ReferenceItem fromJson(String kind, Map<String, dynamic> json) {
    final id = (json['id'] as num).toInt();
    final name = (json['name'] ?? json['material'] ?? json['number'] ?? id).toString();
    final parent = json['parent_id'] ?? json['partner_id'];
    final extra = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('name')
      ..remove('name_en');
    return ReferenceItem(
      kind: kind,
      id: id,
      name: name,
      nameEn: json['name_en']?.toString(),
      parentId: parent is num ? parent.toInt() : null,
      extra: extra,
    );
  }
}

/// A single `value → label` choice of a server choice list.
class ChoiceRow {
  const ChoiceRow({required this.key, required this.value, required this.label, this.labelAr, this.position = 0});

  final String key;
  final String value;
  final String label;
  final String? labelAr;
  final int position;

  String labelFor(String languageCode) =>
      languageCode == 'ar' && (labelAr?.isNotEmpty ?? false) ? labelAr! : label;

  Map<String, Object?> toRow() => {
        'key': key,
        'value': value,
        'label': label,
        'label_ar': labelAr,
        'position': position,
      };

  static ChoiceRow fromRow(Map<String, Object?> row) => ChoiceRow(
        key: row['key'] as String,
        value: row['value'] as String,
        label: (row['label'] as String?) ?? '',
        labelAr: row['label_ar'] as String?,
        position: (row['position'] as int?) ?? 0,
      );
}
