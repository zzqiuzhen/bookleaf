import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/demo_data.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';
import 'ui/glass_tab_bar.dart';
import 'ui/library_page.dart';
import 'ui/reading_now_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.instance.load();
  final store = await LibraryStore.open();
  await seedDemoLibrary(store);
  runApp(BookLeafApp(store: store));
}

const kAccent = Color(0xFFFA5C2E);

class BookLeafApp extends StatelessWidget {
  const BookLeafApp({super.key, required this.store});
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: '书卷',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: kAccent,
        primaryContrastingColor: CupertinoColors.white,
        barBackgroundColor:
            CupertinoColors.systemBackground.color.withOpacity(0.94),
        scaffoldBackgroundColor: CupertinoColors.systemBackground.color,
        textTheme: const CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      home: RootTabs(store: store),
    );
  }
}

class RootTabs extends StatefulWidget {
  const RootTabs({super.key, required this.store});
  final LibraryStore store;

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;

  static const _items = [
    GlassTabItem(
      icon: CupertinoIcons.book,
      activeIcon: CupertinoIcons.book_fill,
      label: '阅读中',
    ),
    GlassTabItem(
      icon: CupertinoIcons.rectangle_stack,
      activeIcon: CupertinoIcons.rectangle_stack_fill,
      label: '书库',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Content runs edge to edge underneath the floating glass bar.
        Positioned.fill(
          child: IndexedStack(
            index: _index,
            children: [
              ReadingNowPage(store: widget.store),
              LibraryPage(store: widget.store),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GlassTabBar(
            index: _index,
            accent: kAccent,
            items: _items,
            onChanged: (i) => setState(() => _index = i),
          ),
        ),
      ],
    );
  }
}
