/// Stable preference IDs, shared by UI and backup validation.
enum AppPalette {
  classic('橙色'),
  cucumber('绿色'),
  sky('蓝色'),
  lavender('紫色');

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
