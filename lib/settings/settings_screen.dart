import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_strings.dart';
import '../l10n/locale_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.settingsTitle),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: s.tabSettings),
              Tab(text: s.tabAbout),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SettingsTab(),
            _AboutTab(),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final notifier = LocaleNotifier.of(context);
    final colors = Theme.of(context).colorScheme;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return ListView(
      children: [
        _SectionHeader(label: s.appearance, colors: colors),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.language, size: 22),
                  const SizedBox(width: 16),
                  Text(s.language),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(value: 'es', label: Text('ES')),
                  ButtonSegment(value: 'en', label: Text('EN')),
                ],
                selected: {notifier.locale.languageCode},
                onSelectionChanged: (v) => notifier.setLocale(Locale(v.first)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.brightness_6_outlined, size: 22),
                  const SizedBox(width: 16),
                  Text(s.themeMode),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                expandedInsets: EdgeInsets.zero,
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto, size: 18),
                    label: Text(s.themeModeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode, size: 18),
                    label: Text(s.themeModeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode, size: 18),
                    label: Text(s.themeModeDark),
                  ),
                ],
                selected: {notifier.themeMode},
                onSelectionChanged: (v) => notifier.setThemeMode(v.first),
              ),
            ],
          ),
        ),
        const Divider(height: 32),
        _SectionHeader(label: s.notifications, colors: colors),
        SwitchListTile(
          secondary: const Icon(Icons.music_note_outlined),
          title: Text(s.viewerSoundLabel),
          subtitle: Text(s.viewerSoundSubtitle),
          value: notifier.viewerSound,
          onChanged: notifier.setViewerSound,
        ),
        const Divider(height: 32),
        _SectionHeader(label: s.account, colors: colors),
        ListTile(
          leading: const Icon(Icons.email_outlined),
          title: Text(email, style: TextStyle(color: colors.outline)),
        ),
        ListTile(
          leading: Icon(Icons.logout, color: colors.error),
          title: Text(s.signOut, style: TextStyle(color: colors.error)),
          onTap: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            FirebaseAuth.instance.signOut();
          },
        ),
      ],
    );
  }
}

class _AboutTab extends StatefulWidget {
  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/icon/icon.png',
              width: 96,
              height: 96,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.appTitle,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _version.isEmpty ? '' : '${s.version} $_version',
            style: textTheme.bodySmall?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              s.aboutDescription,
              style: textTheme.bodyMedium?.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            '©jugomo - 2026',
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colors.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.colors});
  final String label;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
