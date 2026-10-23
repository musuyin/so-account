/// Stable preference IDs, shared by UI and backup validation.
enum AppPalette {
  classic('经典暖白'),
  cucumber('夏日黄瓜花'),
  sky('晴空浅蓝'),
  lavender('雾紫花园');

  const AppPalette(this.label);
  final String label;

  static AppPalette parse(String? value) =>
      values.where((palette) => palette.name == value).firstOrNull ?? cucumber;
}

bool validAppearancePreference(String key, String value) => switch (key) {
  'theme' => ['system', 'light', 'dark'].contains(value),
  'palette' => AppPalette.values.any((palette) => palette.name == value),
  _ => false,
};
