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
  final store = LibraryStore(Directory(p.join(support.path, 'AIReader')));
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
        return MaterialApp(
          title: 'AI Reader',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF4F5BD5),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF4F5BD5),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          home: ShelfScreen(settings: settings, store: store),
        );
      },
    );
  }
}
