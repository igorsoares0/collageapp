/// Template format helpers shared by Discover, Preview and Projects: the
/// published aspect contract, its human labels, and slide counts.
library;

const Map<String, double> _kPresets = {
  'story': 9 / 16,
  'reel': 9 / 16,
  'portrait': 4 / 5,
  'post': 4 / 5,
  'square': 1.0,
  'landscape': 16 / 9,
};

/// The card's shape IS the template's shape, so the artwork fills it edge to
/// edge with nothing left over to letterbox.
///
/// [aspect] is the published `TemplateSummary.aspectRatio` contract — either
/// a named preset or a plain `W:H` — so a tile is sized before any template
/// loads. A name nobody recognises falls back to the dominant format rather
/// than guessing: an unknown template renders as a story.
double aspectRatioOf(String value) {
  final preset = _kPresets[value.trim().toLowerCase()];
  if (preset != null) return preset;
  final parts = value.split(':');
  if (parts.length == 2) {
    final w = double.tryParse(parts[0].trim());
    final h = double.tryParse(parts[1].trim());
    if (w != null && h != null && w > 0 && h > 0) return w / h;
  }
  return 9 / 16;
}

/// "4:5", "9:16", "1:1" — the ratio as people say it.
String ratioLabelOf(String value) {
  final a = aspectRatioOf(value);
  for (final (ratio, label) in const [
    (9 / 16, '9:16'),
    (4 / 5, '4:5'),
    (1.0, '1:1'),
    (16 / 9, '16:9'),
    (3 / 4, '3:4'),
    (2 / 3, '2:3'),
  ]) {
    if ((a - ratio).abs() < 0.005) return label;
  }
  final raw = value.trim();
  return raw.contains(':') ? raw : '9:16';
}

/// "Story", "Portrait", "Square", "Landscape" — the format's name.
String formatNameOf(String value) => switch (ratioLabelOf(value)) {
  '9:16' => 'Story',
  '4:5' || '3:4' || '2:3' => 'Portrait',
  '1:1' => 'Square',
  _ => 'Landscape',
};

/// "5 slides" / "1 slide".
String slidesLabel(int count) => count == 1 ? '1 slide' : '$count slides';

/// "4:5 · 5 slides" — or just the ratio while the count is unknown.
String metaLabel(String aspect, int? slides) => slides == null
    ? ratioLabelOf(aspect)
    : '${ratioLabelOf(aspect)} · ${slidesLabel(slides)}';

/// Spelled-out small counts for headlines ("Five slides, ready.").
String spelledCount(int n) {
  const words = [
    'Zero',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
  ];
  return n >= 0 && n < words.length ? words[n] : '$n';
}
