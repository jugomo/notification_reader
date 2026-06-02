import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends StatefulWidget {
  const LocaleProvider({super.key, required this.child});
  final Widget child;

  @override
  State<LocaleProvider> createState() => _LocaleProviderState();
}

class _LocaleProviderState extends State<LocaleProvider> {
  Locale _locale = const Locale('es');
  ThemeMode _themeMode = ThemeMode.system;
  bool _viewerSound = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    final theme = prefs.getString('themeMode');
    if (!mounted) return;
    setState(() {
      if (code != null) _locale = Locale(code);
      if (theme != null) {
        _themeMode = switch (theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      }
      _viewerSound = prefs.getBool('viewerSound') ?? true;
    });
  }

  Future<void> setLocale(Locale locale) async {
    setState(() => _locale = locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    final key = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('themeMode', key);
  }

  Future<void> setViewerSound(bool enabled) async {
    setState(() => _viewerSound = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('viewerSound', enabled);
  }

  @override
  Widget build(BuildContext context) => LocaleNotifier(
        locale: _locale,
        themeMode: _themeMode,
        viewerSound: _viewerSound,
        setLocale: setLocale,
        setThemeMode: setThemeMode,
        setViewerSound: setViewerSound,
        child: widget.child,
      );
}

class LocaleNotifier extends InheritedWidget {
  const LocaleNotifier({
    super.key,
    required this.locale,
    required this.themeMode,
    required this.viewerSound,
    required this.setLocale,
    required this.setThemeMode,
    required this.setViewerSound,
    required super.child,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final bool viewerSound;
  final Future<void> Function(Locale) setLocale;
  final Future<void> Function(ThemeMode) setThemeMode;
  final Future<void> Function(bool) setViewerSound;

  static LocaleNotifier of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleNotifier>()!;

  @override
  bool updateShouldNotify(LocaleNotifier old) =>
      old.locale != locale || old.themeMode != themeMode || old.viewerSound != viewerSound;
}
