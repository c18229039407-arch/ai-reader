import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'screens/shelf/shelf_screen.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final support = await getApplicationSupportDirectory();
  final store = LibraryStore(Directory(p.join(support.path, 'AIReader')),
      deviceId: settings.deviceId);
  await store.init();
  runApp(AIReaderApp(settings: settings, store: store));
}

class AIReaderApp extends StatelessWidget {
  const AIReaderApp({super.key, required this.settings, required this.store});

  final SettingsStore settings;
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final mode = switch (settings.readerTheme) {
          1 => ThemeMode.light,
          2 => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        // 「林间」森林绿主题
        const seed = Color(0xFF2E6B4F);
        ThemeData themed(Brightness b) {
          final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
          return ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            scaffoldBackgroundColor: b == Brightness.light
                ? const Color(0xFFF7F6F2) // 暖白纸感
                : null,
            appBarTheme: AppBarTheme(
              backgroundColor:
                  b == Brightness.light ? const Color(0xFFF7F6F2) : null,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            snackBarTheme:
                const SnackBarThemeData(behavior: SnackBarBehavior.floating),
            cardTheme: const CardThemeData(
                elevation: 0, surfaceTintColor: Colors.transparent),
          );
        }

        return MaterialApp(
          title: '林间阅读',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: themed(Brightness.light),
          darkTheme: themed(Brightness.dark),
          home: ShelfScreen(settings: settings, store: store),
        );
      },
    );
  }
}
