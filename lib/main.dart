import 'package:flutter/material.dart';
import 'utils/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/other_leagues_screen.dart';
import 'screens/slot_screen.dart';
import 'providers/app_state.dart';
import 'screens/schedule_screen.dart';
import 'screens/hub_screens.dart';
import 'widgets/player_avatar.dart';
import 'utils/standings.dart' show teamColor;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FaceSet.instance.load(); // 選手の顔アイコンのセット
  // 顔アイコンのユニフォーム：選手の球団の色とロゴ（いま開いているプレイデータ）
  FaceSet.instance.uniformOf = (p) {
    final app = currentApp;
    if (app == null) return null;
    for (final t in app.teams) {
      if (t.players.contains(p)) return (teamColor(app.teams, t), t.logo);
    }
    return null;
  };
  runApp(const NpbPennantApp());
}

class NpbPennantApp extends StatelessWidget {
  const NpbPennantApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Authentic Baseball 2026',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.modernLight,
      scrollBehavior: const _AppScroll(), // 縦にすべる画面は、右にスクロールバーをいつも出す
      // スマホ（幅600未満）は文字・余白を詰めて、1画面の情報を増やす
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        if (mq.size.shortestSide >= 600) return child!;
        // 端末のナビゲーションバーの分だけ全画面を上げる（下のボタンが隠れて押せなくならないように）。
        // 内側の SafeArea が二重に空けないよう、下の余白は MediaQuery から外す
        final navBar = mq.viewPadding.bottom;
        return ColoredBox(
          color: Colors.black,
          child: Padding(
            padding: EdgeInsets.only(bottom: navBar),
            child: MediaQuery(
              data: mq.removeViewPadding(removeBottom: true).removePadding(removeBottom: true).copyWith(
                viewInsets: mq.viewInsets.copyWith(bottom: (mq.viewInsets.bottom - navBar).clamp(0.0, double.infinity)),
                textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * 0.88)),
              child: Theme(data: AppTheme.compact(Theme.of(context)), child: child!),
            ),
          ),
        );
      },
      // 最初はプレイデータ1〜3を選ぶ
      home: SlotScreen(mainOf: (app) => MainTabNavigator(appState: app)),
    );
  }
}

class MainTabNavigator extends StatefulWidget {
  final AppState appState;
  const MainTabNavigator({Key? key, required this.appState}) : super(key: key);

  @override
  State<MainTabNavigator> createState() => _MainTabNavigatorState();
}

class _MainTabNavigatorState extends State<MainTabNavigator> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(appState: widget.appState, onNavigate: (i) => setState(() => _currentIndex = i)),
      ScheduleScreen(appState: widget.appState),
      TeamHubScreen(appState: widget.appState),
      FrontHubScreen(appState: widget.appState),
      DataHubScreen(appState: widget.appState),
      OtherLeaguesScreen(appState: widget.appState),
    ];
    const items = [
      (Icons.home_outlined, Icons.home, 'ホーム'),
      (Icons.calendar_month_outlined, Icons.calendar_month, '日程'),
      (Icons.groups_outlined, Icons.groups, 'チーム'),
      (Icons.business_center_outlined, Icons.business_center, 'フロント'),
      (Icons.insights_outlined, Icons.insights, 'データ'),
      (Icons.public_outlined, Icons.public, '他リーグ'),
    ];

    return LayoutBuilder(builder: (context, c) {
      // 広い画面: 左の縦メニュー / 狭い画面: 下のタブ
      if (c.maxWidth >= 900) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              backgroundColor: const Color(0xFF0B1626),
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              labelType: NavigationRailLabelType.all,
              indicatorColor: const Color(0xFF18324F),
              selectedIconTheme: const IconThemeData(color: Color(0xFFC6F24E)),
              unselectedIconTheme: const IconThemeData(color: Color(0xFF8EA3BF)),
              selectedLabelTextStyle: const TextStyle(color: Color(0xFFC6F24E), fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelTextStyle: const TextStyle(color: Color(0xFF8EA3BF), fontSize: 12),
              leading: const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 16),
                child: Text('P26', style: TextStyle(color: Color(0xFFC6F24E), fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              destinations: [for (final it in items) NavigationRailDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3))],
            ),
            Expanded(child: KeyedSubtree(key: PageStorageKey('main_$_currentIndex'), child: screens[_currentIndex])),
          ]),
        );
      }
      return Scaffold(
        body: KeyedSubtree(key: PageStorageKey('main_$_currentIndex'), child: screens[_currentIndex]), // タブを替えて戻ってもスクロールの位置を覚えておく
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          iconSize: 22,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          onTap: (index) => setState(() => _currentIndex = index),
          items: [for (final it in items) BottomNavigationBarItem(icon: Icon(it.$1), activeIcon: Icon(it.$2), label: it.$3)],
        ),
      );
    });
  }
}
/// 縦にすべる画面は、右にスクロールバーをいつも出す（横にすべるものは出さない）
class _AppScroll extends MaterialScrollBehavior {
  const _AppScroll();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return child;
    return Scrollbar(controller: details.controller, thumbVisibility: true, thickness: 4, radius: const Radius.circular(2), child: child);
  }
}
