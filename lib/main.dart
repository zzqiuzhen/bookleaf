import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/demo_data.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';
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

class RootTabs extends StatelessWidget {
  const RootTabs({super.key, required this.store});
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        activeColor: kAccent,
        inactiveColor: CupertinoColors.secondaryLabel.resolveFrom(context),
        backgroundColor:
            CupertinoColors.systemBackground.color.withOpacity(0.96),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.book, size: 23),
            activeIcon: Icon(CupertinoIcons.book_fill, size: 23),
            label: '阅读中',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.rectangle_stack, size: 23),
            activeIcon: Icon(CupertinoIcons.rectangle_stack_fill, size: 23),
            label: '书库',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        if (index == 0) {
          return CupertinoTabView(
            builder: (_) => ReadingNowPage(store: store),
          );
        }
        return CupertinoTabView(
          builder: (_) => LibraryPage(store: store),
        );
      },
    );
  }
}
