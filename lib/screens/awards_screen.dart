import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../widgets/awards_view.dart';

/// 年間の表彰（優勝・日本シリーズ・タイトル・MVP・新人王・ベストナイン・ゴールデングラブ・沢村賞など）
class AwardsScreen extends StatefulWidget {
  final AppState appState;
  final int year;
  const AwardsScreen({super.key, required this.appState, required this.year});

  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

class _AwardsScreenState extends State<AwardsScreen> {
  late final Future<Map<String, dynamic>?> _future = widget.appState.loadAwards(widget.year);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: awardsBg,
      appBar: AppBar(
        backgroundColor: awardsNavy,
        foregroundColor: Colors.white,
        title: Text('${widget.year}年 表彰・タイトル発表', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final aw = snap.data;
          if (aw == null) return const Center(child: Text('この年の表彰はまだありません', style: TextStyle(color: awardsSub)));
          return SeasonAwardsBody(app: widget.appState, year: widget.year, awards: aw);
        },
      ),
    );
  }
}
