import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apple Music / iTunes inspired theme for HiTune.
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  // Most screens are styled dark-first (hardcoded dark surfaces + white
  // text), so dark is the default; light mode can be toggled in settings.
  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('is_dark_mode') ?? true;
    notifyListeners();
    _updateSystemUI();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
    notifyListeners();
    _updateSystemUI();
  }

  void _updateSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: _isDarkMode ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _isDarkMode ? _iosBlack : _iosLightBackground,
        systemNavigationBarIconBrightness: _isDarkMode ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  // Brand palette pulled from the HiTune logo — icy cyan glow on the
  // left, magenta glow on the right.
  static const Color _brandCyan = Color(0xFF0FA8D4);
  static const Color _brandPink = Color(0xFFE56BD8);
  static const Color _iosLightBackground = Color(0xFFF2F2F7);
  static const Color _iosWhite = Colors.white;
  static const Color _iosLightGray = Color(0xFF8E8E93);
  static const Color _iosBlack = Color(0xFF000000);
  static const Color _iosDarkSurface = Color(0xFF1C1C1E);
  static const Color _iosDarkElevated = Color(0xFF2C2C2E);
  static const Color _iosDarkGray = Color(0xFF8E8E93);

  static const Color _iosLabel = Color(0xFF1C1C1E);

  static TextTheme _buildTextTheme(Color text, Color muted) {
    return TextTheme(
      displayLarge: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: text, letterSpacing: -1.0),
      displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.8),
      displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.5),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.4),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.3),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.2),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.1),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: text, letterSpacing: -0.2),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: text, letterSpacing: -0.2),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: muted, letterSpacing: -0.1),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.1),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.0),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.0),
    );
  }

  static ThemeData _buildBaseTheme(ColorScheme colorScheme, bool isDark) {
    final bg = isDark ? _iosBlack : _iosLightBackground;
    final surface = isDark ? _iosDarkSurface : _iosWhite;
    final elevated = isDark ? _iosDarkElevated : _iosWhite;
    final text = isDark ? Colors.white : _iosLabel;
    final muted = isDark ? _iosDarkGray : _iosLightGray;
    final divider = isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      canvasColor: surface,
      textTheme: _buildTextTheme(text, muted),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.4),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? _iosDarkSurface.withValues(alpha: 0.95) : _iosWhite.withValues(alpha: 0.95),
        elevation: 0,
        height: 56,
        indicatorColor: _brandCyan.withValues(alpha: 0.12),
        shadowColor: Colors.black.withValues(alpha: 0.05),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? _brandCyan : muted,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.1,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? _brandCyan : muted, size: 24);
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? _iosDarkSurface : _iosWhite,
        selectedItemColor: _brandCyan,
        unselectedItemColor: muted,
        selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _brandCyan,
        inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.12),
        thumbColor: _brandCyan,
        overlayColor: _brandCyan.withValues(alpha: 0.15),
        trackHeight: 3.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      iconTheme: IconThemeData(color: text, size: 24),
      dividerTheme: DividerThemeData(color: divider, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: muted, fontSize: 15),
        prefixIconColor: muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandCyan,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _brandCyan, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        selectedColor: _brandCyan,
        labelStyle: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        // No tileColor — several screens draw their own dark surfaces and a
        // themed (white in light mode) tile background made white text
        // invisible on SwitchListTile / CheckboxListTile / ListTile.
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _brandCyan,
      brightness: Brightness.light,
    ).copyWith(
      primary: _brandCyan,
      secondary: _brandPink,
      surface: _iosWhite,
      onSurface: _iosLabel,
      surfaceContainer: _iosWhite,
      surfaceContainerHigh: _iosWhite,
    );
    return _buildBaseTheme(colorScheme, false);
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _brandCyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _brandCyan,
      secondary: _brandPink,
      surface: _iosDarkSurface,
      onSurface: Colors.white,
      surfaceContainer: _iosDarkElevated,
      surfaceContainerHigh: _iosDarkElevated,
    );
    return _buildBaseTheme(colorScheme, true);
  }
}
