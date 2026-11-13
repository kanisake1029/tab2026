import 'dart:math';
import '../engine/growth_curve.dart';
import 'practice_picker.dart';
import '../models/league_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../engine/growth_engine.dart';
import '../utils/grade_utils.dart';
import '../utils/app_theme.dart';
import '../utils/salary_utils.dart';
import 'condition_face.dart';
import 'scout_report.dart';
import '../providers/app_state.dart';

class PlayerDetailDialog extends StatefulWidget {
  final Player player;
  final dynamic appState;
  final bool isReadOnly;
  final dynamic team;
  final VoidCallback? onRosterChanged;
  const PlayerDetailDialog({Key? key, required this.player, required this.appState, this.isReadOnly = false, this.team, this.onRosterChanged}) : super(key: key);

  @override
  State<PlayerDetailDialog> createState() => _PlayerDetailDialogState();
}

class _PlayerDetailDialogState extends State<PlayerDetailDialog> {
  late Player p;

  @override
  void initState() {
    super.initState();
    p = widget.player;
  }

  DateTime? _parseDate(String d) {
    try {
      d = d.replaceAll('/', '-');
      return DateTime.parse(d);
    } catch (e) {
      return null;
    }
  }

  void _syncDates({bool fromBirthDate = false, bool fromProYears = false, bool fromDraft = false}) {
    DateTime baseDate = DateTime(widget.appState.startYear, 1, 1);
    
    int baseAge = 19;
    if (p.draftType == 'B') baseAge = 23;
    if (p.draftType == 'C') baseAge = p.draftCustomAge;

    DateTime? bDate = _parseDate(p.birthDate);
    if (bDate == null) return;

    if (fromBirthDate || fromDraft) {
      int age = baseDate.year - bDate.year;
      if (baseDate.month < bDate.month || (baseDate.month == bDate.month && baseDate.day < bDate.day)) {
        age--;
      }
      p.age = age;

      int newProYear = p.age - baseAge + 1;
      if (newProYear < 1) {
        newProYear = 1;
        p.age = baseAge;
        
        int birthYearOffset = (baseDate.month < bDate.month || (baseDate.month == bDate.month && baseDate.day < bDate.day)) ? 1 : 0;
        int targetBirthYear = baseDate.year - p.age - birthYearOffset;
        
        bDate = DateTime(targetBirthYear, bDate.month, bDate.day);
        p.birthDate = '${bDate.year}-${bDate.month.toString().padLeft(2, '0')}-${bDate.day.toString().padLeft(2, '0')}';
      }
      p.proYears = newProYear;

    } else if (fromProYears) {
      if (p.proYears < 1) p.proYears = 1;
      p.age = p.proYears + baseAge - 1;
      
      int birthYearOffset = (baseDate.month < bDate.month || (baseDate.month == bDate.month && baseDate.day < bDate.day)) ? 1 : 0;
      int targetBirthYear = baseDate.year - p.age - birthYearOffset;
      
      bDate = DateTime(targetBirthYear, bDate.month, bDate.day);
      p.birthDate = '${bDate.year}-${bDate.month.toString().padLeft(2, '0')}-${bDate.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 閲覧用: スカウティングレポート形式（編集時は従来のタブ形式）
    if (widget.isReadOnly) {
      final size = MediaQuery.of(context).size;
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1180, maxHeight: size.height * 0.92),
          child: ScoutReport(
            player: p,
            appState: widget.appState,
            team: widget.team,
            // 操作欄は練習メニューと、1軍・2軍（育成なら支配下登録）だけ。登録名・背番号・ポジション・二刀流は名前を押して変える
            actions: widget.team != null ? _buildActions() : null,
            onEditName: widget.team?.id == widget.appState.myTeamId ? _editProfile : null,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          width: 900,
          height: 650,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('#${p.uniformText} ${p.registeredName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    TabBar(
                      indicatorColor: Colors.blue,
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey.shade600,
                      tabs: [
                        Tab(text: '基本情報'),
                        Tab(text: '野手能力'),
                        Tab(text: '投手能力'),
                        const Tab(text: '成績'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildBasicTab(),
                          _buildFielderTab(),
                          _buildPitcherTab(),
                          _buildStatsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.team != null && widget.isReadOnly)
              Column(
                children: [
                  Divider(color: Colors.grey.shade300),
                  _buildActions(),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// 才能・向上心の欄（読み取りだけならランクと数値、編集できるなら入力欄）
  Widget _traitBox(String label, int v, ValueChanged<int> set) {
    final g = GradeUtils.getGrade(v);
    if (widget.isReadOnly) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text.rich(TextSpan(children: [TextSpan(text: g, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))), TextSpan(text: ' $v')])),
      );
    }
    return TextFormField(
      key: ValueKey('trait_$label'),
      initialValue: '$v',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: '$label（1〜100）'),
      onChanged: (s) {
        final n = int.tryParse(s);
        if (n != null) setState(() => set(n.clamp(1, 100)));
      },
    );
  }

  /// 二刀流の切り替え（やめたら本職でない起用から外す）
  void _applyTwoWay(bool v) {
    {
      {
        p.twoWay = v;
        final t = widget.team;
        if (!v && t != null) {
          // 二刀流をやめたら、本職でない起用から外す
          if (!p.isPitcher) {
            for (var i = 0; i < t.rotation.length; i++) { if (t.rotation[i] == p.id) t.rotation[i] = ''; }
            for (var i = 0; i < t.winningPattern.length; i++) { if (t.winningPattern[i] == p.id) t.winningPattern[i] = ''; }
            t.autoFillPitchingStaff();
          } else {
            t.lineup.removeWhere((l) => l.playerId == p.id && l.position != '投');
          }
          t.refreshActive26();
        }
        widget.appState.updateAndSave();
        if (widget.onRosterChanged != null) widget.onRosterChanged!();
      }
    }
  }

  /// 練習指示と、1軍昇格・2軍降格のボタン
  /// 登録名（表示の形式・オリジナルの名前）・背番号・メインポジションを変える（自球団の選手）

  Future<void> _editProfile() async {
    var type = p.nameType;
    final custom = TextEditingController(text: p.customName);
    final app = widget.appState as AppState;
    final free = app.numberFreeNow(p);
    final number = TextEditingController(text: uniformLabel(app.numberNextSeason(p)));
    var pos = p.isPitcher ? '投手' : p.mainPosition;
    var twoWay = p.twoWay;
    String? err;
    const types = [('A', '姓 名'), ('B', '姓名（つなげる）'), ('C', '姓＋名の頭文字'), ('D', '名前だけ'), ('E', 'オリジナル（入力）'), ('F', '名・姓（外国人）')];
    const positions = ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          String preview() {
            final q = Player.fromJson({...p.toJson(), 'nameType': type, 'customName': custom.text});
            return q.registeredName;
          }

          return AlertDialog(
            title: const Text('登録名・背番号・ポジション'),
            scrollable: true,
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${p.lastName}　${p.firstName}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '登録名の形式'),
                  value: type,
                  items: [for (final t in types) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
                  onChanged: (v) => set(() => type = v ?? type),
                ),
                if (type == 'E')
                  TextField(controller: custom, decoration: const InputDecoration(labelText: 'オリジナルの登録名'), onChanged: (_) => set(() {})),
                Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text('登録名：${preview()}', style: const TextStyle(fontWeight: FontWeight.w800))),
                TextField(
                  controller: number,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: free ? '背番号（すぐ変わります）' : '来季の背番号（2月1日から）',
                    helperText: free
                        ? (app.isOpeningNumberDay
                            ? '今年だけ特別に、今日（開幕日）はすぐ変えられます'
                            : (app.isOffseasonNumberFree
                                ? 'オフ期間（11/1〜1/31）はすぐ変わり、変更は経歴に残りません'
                                : '入団・移籍したばかりなので、${p.numberFreeUntil.substring(5).replaceAll('-', '/')}まではすぐ変わり、変更は経歴に残りません'))
                        : 'いまは #${p.uniformText}。背番号の変更は毎年2月1日から（チーム → 全選手 →「背番号」で一括も）',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'メインポジション'),
                  value: pos,
                  items: [for (final x in p.isPitcher ? const ['投手'] : positions) DropdownMenuItem(value: x, child: Text(x))],
                  onChanged: p.isPitcher ? null : (v) => set(() => pos = v ?? pos),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.isPitcher ? '二刀流（野手としても起用）' : '二刀流（投手としても起用）', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  subtitle: Text(p.isPitcher ? 'オーダー（打順・DH）にも入れられる' : '先発ローテ・中継ぎにも入れられる', style: const TextStyle(fontSize: 11.5)),
                  value: twoWay,
                  onChanged: (v) => set(() => twoWay = v),
                ),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
              FilledButton(
                onPressed: () {
                  final n = parseUniform(number.text);
                  if (n == null) return set(() => err = '背番号は 00・0〜999 で入力してください');
                  if (type == 'E' && custom.text.trim().isEmpty) return set(() => err = 'オリジナルの登録名を入力してください');
                  final Team? t = widget.team as Team?;
                  if (t != null) {
                    final e = app.setNumber(t, p, n);
                    if (e != null) return set(() => err = e);
                  }
                  Navigator.pop(c, true);
                  p.nameType = type;
                  p.customName = custom.text.trim();
                  if (!p.isPitcher) p.mainPos = pos;
                  if (twoWay != p.twoWay) _applyTwoWay(twoWay);
                },
                child: const Text('変更する'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    setState(() {});
    widget.appState.updateAndSave();
    if (widget.onRosterChanged != null) widget.onRosterChanged!();
  }

  Widget _buildActions() {
    return
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 練習メニュー：押すと、能力のまとまりごとに今の値を添えて選べる（専門外の練習も選べる）
                      OutlinedButton(
                        onPressed: () async {
                          final v = await showPracticePicker(context, p);
                          if (v == null) return;
                          setState(() => p.practiceInstruction = v);
                          if (widget.onRosterChanged != null) widget.onRosterChanged!();
                        },
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          const Text('練習メニュー', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                          Text(
                            GrowthEngine.practiceOptions(p).contains(p.practiceInstruction) && p.practiceInstruction != 'おまかせ' ? '${p.practiceInstruction}　${GrowthEngine.menuValue(p, p.practiceInstruction)}' : 'おまかせ（${GrowthEngine.autoPractice(p)}）',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      // 育成選手は「支配下登録」。登録すると「1軍へ昇格」に変わる
                      if (p.ikusei && widget.team!.id == widget.appState.myTeamId)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('支配下登録'),
                                content: Text('${p.registeredName}を支配下登録しますか？\n背番号は2桁になり、支配下の枠（70人）を1つ使います。'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('登録する')),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                            final err = widget.appState.promoteIkusei(p);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? '${p.registeredName}を支配下登録しました（背番号${p.uniformNumber}）')));
                            setState(() {});
                            if (widget.onRosterChanged != null) widget.onRosterChanged!();
                          },
                          child: const Text('支配下登録', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.team!.roster1G.contains(p.id) ? Colors.redAccent : Colors.cyan.shade800,
                        ),
                                                onPressed: () {
                          setState(() {
                            if (widget.team!.roster1G.contains(p.id)) {
                              // Demote to 2G
                              final t = widget.team!;
                              t.roster1G.remove(p.id);
                              t.manualBenchOut.remove(p.id);
                              for (var i = 0; i < t.rotation.length; i++) { if (t.rotation[i] == p.id) t.rotation[i] = ''; }
                              for (var i = 0; i < t.winningPattern.length; i++) { if (t.winningPattern[i] == p.id) t.winningPattern[i] = ''; }
                              t.autoFillPitchingStaff();
                              t.refreshActive26();
                              p.lastDemotedDate = widget.appState.currentDate.toIso8601String();
                            } else {
                              // Promote to 1G
                              if (p.ikusei) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('育成選手は、支配下登録しないと1軍に上がれません（フロント → 補強 → 戦力外・育成）')));
                                return;
                              }
                              // 1. Check max 31
                              if (widget.team!.roster1G.length >= 31) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('1軍枠は31人までです')));
                                return;
                              }
                              // 2. Check 10-day penalty
                              if (p.lastDemotedDate != null) {
                                DateTime demoted = DateTime.parse(p.lastDemotedDate!);
                                int daysDiff = widget.appState.currentDate.difference(demoted).inDays;
                                if (daysDiff > 0 && daysDiff < 10) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('抹消後10日間は再登録できません（残り${10 - daysDiff}日）')));
                                  return;
                                }
                              }
                              // 3. Check foreigner limit (Max 5)
                              if (p.foreignSlot) {
                                int foreignCount = 0;
                                for (String id in widget.team!.roster1G) {
                                  var fp = widget.team!.players.firstWhere((pl) => pl.id == id);
                                  if (fp.foreignSlot) foreignCount++;
                                }
                                if (!LeagueRules.under1G(foreignCount)) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('1軍の外国人枠は${LeagueRules.foreign1G}人までです')));
                                  return;
                                }
                              }

                              widget.team!.roster1G.add(p.id);
                              // ベンチ入り26人は自動で作り直す（あふれた分は控えの下位から自動でベンチ外）
                              widget.team!.refreshActive26();
                            }
                            if (widget.onRosterChanged != null) widget.onRosterChanged!();
                          });
                        },
                        child: Text(widget.team!.roster1G.contains(p.id) ? '2軍へ降格' : '1軍へ昇格', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ]
                  );
  }

  Widget _buildBasicTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildTextField('姓', p.lastName, (val) => p.lastName = val))),
              const SizedBox(width: 16),
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildTextField('名', p.firstName, (val) => p.firstName = val))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '表示名パターン'),
                  value: p.nameType,
                  dropdownColor: Colors.white,
                  items: const [
                    DropdownMenuItem(value: 'A', child: Text('A: 姓 名')),
                    DropdownMenuItem(value: 'B', child: Text('B: 姓名')),
                    DropdownMenuItem(value: 'C', child: Text('C: 姓+名の頭文字')),
                    DropdownMenuItem(value: 'D', child: Text('D: 名前のみ')),
                    DropdownMenuItem(value: 'E', child: Text('E: オリジナル')),
                    DropdownMenuItem(value: 'F', child: Text('F: 名・姓（外国人）')),
                  ],
                  onChanged: (val) => setState(() => p.nameType = val!),
                ),
              ),
              const SizedBox(width: 16),
              if (p.nameType == 'E')
                Expanded(child: _buildTextField('オリジナル表示名', p.customName, (val) => p.customName = val))
              else
                Expanded(child: Container()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: TextFormField(
                    initialValue: p.uniformText,
                    enabled: !widget.isReadOnly,
                    decoration: const InputDecoration(labelText: '背番号（00, 0〜999）', isDense: true),
                    onChanged: (val) {
                      final v = parseUniform(val);
                      if (v != null) {
                        p.uniformNumber = v;
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'メインポジション'),
                    value: p.isPitcher ? '投手' : p.mainPosition,
                    dropdownColor: Colors.white,
                    items: (p.isPitcher ? ['投手'] : ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'])
                        .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() { if (val != null) p.mainPos = val; }),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '国籍'),
                    value: p.nationality,
                    dropdownColor: Colors.white,
                    items: ['日本', '海外'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() => p.nationality = val!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '来歴'),
                    value: p.draftType,
                    dropdownColor: Colors.white,
                    items: const [
                      DropdownMenuItem(value: 'A', child: Text('A: 高卒')),
                      DropdownMenuItem(value: 'B', child: Text('B: 大卒')),
                      DropdownMenuItem(value: 'C', child: Text('C: 社卒・その他')),
                    ],
                    onChanged: (val) => setState(() {
                      p.draftType = val!;
                      _syncDates(fromDraft: true);
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              if (p.draftType == 'C')
                Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildNumberField('1年目の年齢', p.draftCustomAge, (val) { p.draftCustomAge = val; _syncDates(fromDraft: true); })))
              else
                Expanded(child: Container()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildTextField('生年月日 (YYYY-MM-DD)', p.birthDate, (val) { p.birthDate = val; _syncDates(fromBirthDate: true); }))),
              const SizedBox(width: 16),
              Expanded(child: _buildNumberField('年齢 (表示のみ)', p.age, (val) {}, enabled: false)),
              const SizedBox(width: 16),
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildNumberField('プロ年数', p.proYears, (val) { p.proYears = val; _syncDates(fromProYears: true); }))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildNumberField('身長 (cm)', p.height, (val) => p.height = val))),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '投 / 打'),
                  value: '${p.throws}/${p.bats}',
                  dropdownColor: Colors.white,
                  items: ['R/R', 'R/L', 'R/S', 'L/L', 'L/R', 'L/S'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() { p.throws = val.split('/')[0]; p.bats = val.split('/')[1]; });
                    if (widget.onRosterChanged != null) widget.onRosterChanged!();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('コンディション', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(children: [
                  _buildEnergyGauge(),
                  _buildCyberGauge('回復力', p.recovery, (v) => setState(() => p.recovery = v.clamp(1, 100))),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(children: [
                  _buildCyberGauge('怪我しにくさ', p.durability, (v) => setState(() => p.durability = v.clamp(1, 100)), labelWidth: 120),
                  _buildCyberGauge('信頼', p.trust, (v) => setState(() => p.trust = v.clamp(1, 100))),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildConditionRow(),
          const SizedBox(height: 24),
          const Text('成長・契約', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          // 才能・向上心（成長率 = 才能の倍率 × 向上心の倍率）。編集できる画面では数値で変えられる
          Row(children: [
            Expanded(child: _traitBox('才能', p.talent, (v) => p.talent = v)),
            const SizedBox(width: 16),
            Expanded(child: _traitBox('向上心', p.ambition, (v) => p.ambition = v)),
            const SizedBox(width: 16),
            Expanded(child: Text('成長率 ×${p.growthRate.toStringAsFixed(2)}\n${GrowthEngine.phaseOf(p).label}', style: const TextStyle(fontSize: 13, height: 1.4))),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                // 成長曲線（全盛期の年齢と長さ）。変えるときは「チーム・選手編集」で
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '成長曲線'),
                  child: Text(GrowthCurve.label(p)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: widget.isReadOnly
                    ? InputDecorator(
                        decoration: const InputDecoration(labelText: '年俸', isDense: true),
                        child: Text(formatSalary(p.salary), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      )
                    : Row(children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('salary_${p.salary}'),
                            initialValue: p.salary.toString(),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: '年俸（万円）', isDense: true, helperText: formatSalary(p.salary)),
                            onChanged: (val) {
                              final v = int.tryParse(val);
                              if (v != null) {
                                p.salary = v.clamp(0, 999999);
                                if (widget.onRosterChanged != null) widget.onRosterChanged!();
                              }
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => p.salary = estimateSalary(p));
                            if (widget.onRosterChanged != null) widget.onRosterChanged!();
                          },
                          child: const Text('自動算出'),
                        ),
                      ]),
              ),
              const SizedBox(width: 16),
              Expanded(child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildNumberField('契約年数', p.contractYears, (val) => p.contractYears = val.clamp(1, 10)))),
            ],
          ),
        ],
      ),
    );
  }

  /// 体力ゲージ（例: 「290/930 S 93」）。ランクは最大値÷10
  Widget _buildEnergyGauge() {
    final rank = p.energyRank;
    final grade = GradeUtils.getGrade(rank);
    final gradeColor = AppTheme.getGradeColor(grade);
    final ratio = p.maxEnergy == 0 ? 0.0 : (p.energy / p.maxEnergy).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 80, child: Text('体力', style: TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              Text('${p.energy}/', style: const TextStyle(color: Colors.black54, fontSize: 14)),
              if (widget.isReadOnly)
                Text('${p.maxEnergy}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14))
              else
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    key: ValueKey('maxEnergy_${p.maxEnergy}'),
                    initialValue: p.maxEnergy.toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    onChanged: (val) {
                      final v = int.tryParse(val);
                      if (v != null) {
                        setState(() {
                          final wasFull = p.energy >= p.maxEnergy;
                          p.maxEnergy = v.clamp(1, 1000);
                          p.energy = wasFull ? p.maxEnergy : p.energy.clamp(0, p.maxEnergy);
                        });
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 32, child: Text('$rank', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right)),
            ],
          ),
          const SizedBox(height: 6),
          // 外側: 最大値（能力）、内側: 現在値の割合
          Stack(children: [
            LinearProgressIndicator(value: rank / 100, backgroundColor: Colors.grey.shade200, color: gradeColor.withOpacity(0.25), minHeight: 5),
            FractionallySizedBox(
              widthFactor: rank / 100,
              child: LinearProgressIndicator(value: ratio, backgroundColor: Colors.transparent, color: ratio < 0.3 ? Colors.redAccent : (ratio < 0.5 ? Colors.orange : gradeColor), minHeight: 5),
            ),
          ]),
        ],
      ),
    );
  }

  /// 調子（5段階）・モチベーション・怪我の表示
  Widget _buildConditionRow() {
    final start = DateTime(widget.appState.startYear, 1, 1);
    final day = (widget.appState.currentDate as DateTime).difference(start).inDays;
    final c = p.conditionOn(day);
    const colors = {-2: Colors.indigo, -1: Colors.blue, 0: Colors.grey, 1: Colors.orange, 2: Colors.redAccent};
    final injury = p.injuryDays <= 0
        ? '健康'
        : '${p.injuryName.isEmpty ? '怪我' : p.injuryName}  全治${p.injuryDays}日（${const {1: '軽度・強行出場可', 2: '中度・出場不可', 3: '重度・出場不可'}[p.injurySeverity] ?? ''}）';
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('調子  ', style: TextStyle(color: Colors.black54)),
          ConditionFace(level: c, size: 20),
          const SizedBox(width: 4),
          Text(Player.conditionLabels[c]!, style: TextStyle(color: colors[c], fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        Text('モチベーション  ${p.motivation}', style: const TextStyle(color: Colors.black87)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('怪我  ', style: TextStyle(color: Colors.black54)),
          Text(injury, style: TextStyle(color: p.injuryDays > 0 ? Colors.redAccent : Colors.green.shade700, fontWeight: FontWeight.bold)),
        ]),
      ],
    );
  }

  Widget _buildFielderTab() { 
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            children: [
              _buildOvrGauge(p.ovr),
              const Divider(),
              _buildTrajectoryStat(),
              _buildDisplayCyberGauge('ミート', p.contact),
              _buildCyberGauge('対左ミート', p.contactLeft, (v) => setState(() => p.contactLeft = v), indent: 24, compact: true),
              _buildCyberGauge('対右ミート', p.contactRight, (v) => setState(() => p.contactRight = v), indent: 24, compact: true),
              _buildCyberGauge('選球眼', p.eye, (v) => setState(() => p.eye = v)),
              _buildCyberGauge('パワー', p.power, (v) => setState(() => p.power = v)),
              _buildCyberGauge('走力', p.run, (v) => setState(() => p.run = v)),
              _buildCyberGauge('肩力', p.arm, (v) => setState(() => p.arm = v)),
              _buildCyberGauge('送球', p.throwAccuracy, (v) => setState(() => p.throwAccuracy = v)),
              _buildCyberGauge('捕球', p.catchSkill, (v) => setState(() => p.catchSkill = v)),
              _buildCyberGauge('チャンス', p.clutch, (v) => setState(() => p.clutch = v)),
            ],
          ),
        ),
        VerticalDivider(color: Colors.grey.shade300),
        Expanded(
          flex: 5,
          child: IgnorePointer(ignoring: widget.isReadOnly, child: SingleChildScrollView(child: _buildFieldingDiamond())),
        )
      ],
    );
  }

  Widget _buildPitcherTab() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            children: [
              _buildOvrGauge(p.ovr),
              const Divider(),
              _buildVelocityGauge(),
              _buildCyberGauge('球威', p.pitchPower, (v) => setState(() => p.pitchPower = v)),
              _buildCyberGauge('制球', p.control, (v) => setState(() => p.control = v)),
              _buildCyberGauge('スタミナ', p.stamina, (v) => setState(() => p.stamina = v)),
              _buildCyberGauge('ピンチ', p.clutchPitching, (v) => setState(() => p.clutchPitching = v)),
              _buildPitchSlider('回転軸(腕の角度)', p.spinAxis.toDouble(), 0, 360, (v) => setState(() => p.spinAxis = v.toInt())),
            ],
          ),
        ),
        VerticalDivider(color: Colors.grey.shade300),
        Expanded(
            flex: 5,
            child: _buildPitchSettingsPanel(),
          )
      ],
    );
  }

  
  Widget _buildPitchSettingsPanel() {
    int totalRatio = p.pitches.fold(0, (sum, pitch) => sum + pitch.ratio);
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildPitchVectorChart(totalRatio),
                const SizedBox(height: 16),
                ...p.pitches.map((pitch) => _buildPitchCard(pitch)).toList(),
                const SizedBox(height: 16),
                if (!widget.isReadOnly)
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        p.pitches.add(Pitch(name: 'ストレート', breakLevel: 50, angle: 0, speed: p.velocity, ratio: 0, sharpness: 50, heaviness: 50));
                      });
                      if (widget.onRosterChanged != null) widget.onRosterChanged!();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('球種を追加'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchVectorChart(int totalRatio) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('変化球ベクトル図', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              width: 200,
              child: CustomPaint(
                painter: PitchVectorPainter(p.pitches),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('投球割合合計:', style: TextStyle(color: Colors.black)),
                Text('${totalRatio}%', style: TextStyle(color: totalRatio == 100 ? Colors.green : (totalRatio > 100 ? Colors.red : Colors.orange), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (totalRatio / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade300,
              color: totalRatio == 100 ? Colors.green : (totalRatio > 100 ? Colors.red : Colors.orange),
              minHeight: 8,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPitchCard(Pitch pitch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: _getPitchColor(pitch.angle), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
        ]
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: IgnorePointer(
                    ignoring: widget.isReadOnly,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('球種名', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: pitch.name,
                          style: const TextStyle(color: Colors.black87),
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (val) {
                            setState(() => pitch.name = val);
                            if (widget.onRosterChanged != null) widget.onRosterChanged!();
                          },
                        ),
                      ],
                    )
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: IgnorePointer(
                    ignoring: widget.isReadOnly,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('球速 (km/h)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: pitch.speed.toString(),
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.black87),
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (val) {
                            setState(() => pitch.speed = int.tryParse(val) ?? pitch.speed);
                            if (widget.onRosterChanged != null) widget.onRosterChanged!();
                          },
                        ),
                      ],
                    )
                  ),
                ),
                if (!widget.isReadOnly)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        p.pitches.remove(pitch);
                      });
                      if (widget.onRosterChanged != null) widget.onRosterChanged!();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: widget.isReadOnly,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('投球割合 (%)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: pitch.ratio.toString(),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.black87),
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (val) {
                        setState(() => pitch.ratio = int.tryParse(val) ?? pitch.ratio);
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      },
                    ),
                  )
                ],
              )
            ),
            const SizedBox(height: 16),
            _buildPitchSlider('変化方向(度)', pitch.angle.toDouble(), 0, 360, (v) => setState(() => pitch.angle = v.toInt())),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  _buildPitchGradeSlider('キレ', pitch.sharpness, (v) => setState(() => pitch.sharpness = v)),
                  _buildPitchGradeSlider('重さ', pitch.heaviness, (v) => setState(() => pitch.heaviness = v)),
                  _buildPitchGradeSlider('変化量', pitch.breakLevel, (v) => setState(() => pitch.breakLevel = v)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildCyberGauge(String label, int value, Function(int) onChanged, {double indent = 0, bool compact = false, double labelWidth = 80}) {
    String grade = GradeUtils.getGrade(value);
    Color gradeColor = AppTheme.getGradeColor(grade);
    double fontSizeLabel = compact ? 13 : 15;

    return Padding(
      padding: EdgeInsets.only(top: 8.0, bottom: 8.0, left: 8 + indent, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: labelWidth, child: Text(label, style: TextStyle(color: Colors.black87, fontSize: fontSizeLabel))),
              const Spacer(),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              if (widget.isReadOnly)
                SizedBox(width: 32, child: Text(value.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right))
              else
                SizedBox(
                  width: 50,
                  child: TextFormField(
                    key: ValueKey('${label}_$value'),
                    initialValue: value.toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    onChanged: (val) {
                      int? v = int.tryParse(val);
                      if (v != null) {
                        onChanged(v.clamp(0, 100));
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: value / 100, backgroundColor: Colors.grey.shade200, color: gradeColor, minHeight: compact ? 3 : 5),
        ],
      ),
    );
  }

  Widget _buildDisplayCyberGauge(String label, int value) {
    String grade = GradeUtils.getGrade(value);
    Color gradeColor = AppTheme.getGradeColor(grade);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 32, child: Text(value.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: value / 100, backgroundColor: Colors.grey.shade200, color: gradeColor, minHeight: 5),
        ],
      ),
    );
  }

      Widget _buildVelocityGauge() {
    int score = ((p.velocity - 120) * 2).clamp(0, 100);
    String grade = GradeUtils.getGrade(score);
    Color gradeColor = AppTheme.getGradeColor(grade);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 50, child: Text('球速', style: TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              if (widget.isReadOnly)
                Text('${p.velocity}km/h', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13))
              else
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    key: ValueKey('velocity_${p.velocity}'),
                    initialValue: p.velocity.toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, suffixText: 'km/h', suffixStyle: TextStyle(color: Colors.black54), contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
                    onChanged: (val) {
                      int? v = int.tryParse(val);
                      if (v != null) {
                        setState(() => p.velocity = v.clamp(80, 175));
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50, 
                child: Text(score.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)
              )
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: score / 100, backgroundColor: Colors.grey.shade200, color: gradeColor, minHeight: 5),
        ],
      ),
    );
  }

  Widget _buildOvrGauge(int ovrValue) {
    String grade = GradeUtils.getGrade(ovrValue);
    Color gradeColor = AppTheme.getGradeColor(grade);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0, left: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 80, child: Text('OVR', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold))),
              const Spacer(),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50, 
                child: Text(ovrValue.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)
              )
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: ovrValue / 100, backgroundColor: Colors.grey.shade200, color: gradeColor, minHeight: 5),
        ],
      ),
    );
  }

  Widget _buildTrajectoryStat() {
    Color tColor = AppTheme.getTrajectoryColor(p.trajectory);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 80, child: Text('弾道', style: TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              if (widget.isReadOnly)
                Text(p.trajectory.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16))
              else
                SizedBox(
                  width: 70,
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: p.trajectory,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8)),
                    items: [1, 2, 3, 4].map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => p.trajectory = val);
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: p.trajectory / 4, backgroundColor: Colors.grey.shade200, color: tColor, minHeight: 5),
        ],
      ),
    );
  }

  Widget _buildPitchGradeSlider(String label, int val, ValueChanged<int> onChanged) {
    String grade = GradeUtils.getGrade(val);
    Color gradeColor = AppTheme.getGradeColor(grade);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              if (widget.isReadOnly)
                SizedBox(width: 32, child: Text(val.toString(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right))
              else
                SizedBox(
                  width: 50,
                  child: TextFormField(
                    key: ValueKey('${label}_$val'),
                    initialValue: val.toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    onChanged: (v) {
                      int? parsed = int.tryParse(v);
                      if (parsed != null) {
                        onChanged(parsed.clamp(0, 100));
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: val / 100, backgroundColor: Colors.grey.shade200, color: gradeColor, minHeight: 5),
        ],
      ),
    );
  }

  Widget _buildPitchSlider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 15))),
              const Spacer(),
              if (widget.isReadOnly)
                Text('${val.toInt()}°', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16))
              else
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    key: ValueKey('${label}_$val'),
                    initialValue: val.toInt().toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, suffixText: '°', contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    onChanged: (v) {
                      double? parsed = double.tryParse(v);
                      if (parsed != null) {
                        onChanged(parsed.clamp(min, max));
                        if (widget.onRosterChanged != null) widget.onRosterChanged!();
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: val / max, backgroundColor: Colors.grey.shade200, color: Colors.grey.shade600, minHeight: 5),
        ],
      ),
    );
  }

  Widget _buildFieldingDiamond() {
    Widget posIcon(String label, int val) {
      String grade = GradeUtils.getGrade(val);
      Color color = AppTheme.getGradeColor(grade);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 4),
                Text(val.toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          )
        ],
      );
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('守備適性', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        SizedBox(
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(200, 200),
                painter: BaseballFieldPainter(),
              ),
              Positioned(top: 115, child: posIcon('投', p.fieldP)),
              Positioned(bottom: 0, child: posIcon('捕', p.fieldC)),
              Positioned(right: 10, bottom: 70, child: posIcon('一', p.field1B)),
              Positioned(right: 55, top: 60, child: posIcon('二', p.field2B)),
              Positioned(left: 10, bottom: 70, child: posIcon('三', p.field3B)),
              Positioned(left: 55, top: 60, child: posIcon('遊', p.fieldSS)),
              Positioned(left: 10, top: 20, child: posIcon('左', p.fieldLF)),
              Positioned(top: 15, child: posIcon('中', p.fieldCF)),
              Positioned(right: 10, top: 20, child: posIcon('右', p.fieldRF)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!widget.isReadOnly) ...[
          const Divider(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildSmallField('投', p.fieldP, (v) => setState(() => p.fieldP = v)),
              _buildSmallField('捕', p.fieldC, (v) => setState(() => p.fieldC = v)),
              _buildSmallField('一', p.field1B, (v) => setState(() => p.field1B = v)),
              _buildSmallField('二', p.field2B, (v) => setState(() => p.field2B = v)),
              _buildSmallField('三', p.field3B, (v) => setState(() => p.field3B = v)),
              _buildSmallField('遊', p.fieldSS, (v) => setState(() => p.fieldSS = v)),
              _buildSmallField('左', p.fieldLF, (v) => setState(() => p.fieldLF = v)),
              _buildSmallField('中', p.fieldCF, (v) => setState(() => p.fieldCF = v)),
              _buildSmallField('右', p.fieldRF, (v) => setState(() => p.fieldRF = v)),
            ],
          )
        ]
      ],
    );
  }

  Widget _buildSmallField(String label, int value, Function(int) onChanged) {
    return SizedBox(
      width: 45,
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        onChanged: (val) {
          int? v = int.tryParse(val);
          if (v != null) {
            onChanged(v.clamp(0, 100));
            if (widget.onRosterChanged != null) widget.onRosterChanged!();
          }
        },
      ),
    );
  }

  Widget _buildTextField(String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextFormField(
        initialValue: value,
        style: const TextStyle(color: Colors.black87),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), isDense: true),
        onChanged: (val) {
          onChanged(val);
          if (widget.onRosterChanged != null) widget.onRosterChanged!();
        },
      ),
    );
  }

  Widget _buildNumberField(String label, int value, Function(int) onChanged, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextFormField(
        initialValue: value.toString(),
        enabled: enabled,
        keyboardType: TextInputType.number,
        style: TextStyle(color: enabled ? Colors.black87 : Colors.grey),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), isDense: true),
        onChanged: (val) {
          int? v = int.tryParse(val);
          if (v != null) {
            onChanged(v);
            if (widget.onRosterChanged != null) widget.onRosterChanged!();
          }
        },
      ),
    );
  }

  Color _getPitchColor(int angle) {
    if (angle == 0 || angle == 90 || angle == 180) return Colors.red;
    if (angle > 0 && angle < 90) return Colors.blue;
    if (angle > 90 && angle <= 180) return Colors.purple;
    return Colors.grey;
  }

  
        Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('過去の成績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          const Text('※ 今後実装予定', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          const Text('今季の野手成績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statBox('試合', p.seasonStats.games.toString()),
              _statBox('打率', p.seasonStats.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')),
              _statBox('打席', p.seasonStats.atBats.toString()),
              _statBox('安打', p.seasonStats.hits.toString()),
              _statBox('本塁打', p.seasonStats.homeRuns.toString()),
              _statBox('打点', p.seasonStats.rbi.toString()),
              _statBox('三振', p.seasonStats.strikeouts.toString()),
              _statBox('四球', p.seasonStats.walks.toString()),
              _statBox('盗塁', p.seasonStats.stolenBases.toString()),
            ],
          ),
          const SizedBox(height: 24),
          const Text('今季の投手成績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statBox('登板', p.seasonStats.apps.toString()),
              _statBox('先発', p.seasonStats.starts.toString()),
              _statBox('防御率', p.seasonStats.era.toStringAsFixed(2)),
              _statBox('勝利', p.seasonStats.wins.toString()),
              _statBox('敗北', p.seasonStats.losses.toString()),
              _statBox('ホールド', p.seasonStats.holds.toString()),
              _statBox('セーブ', p.seasonStats.saves.toString()),
              _statBox('投球回', (p.seasonStats.inningsPitched / 3).toStringAsFixed(1)),
              _statBox('奪三振', p.seasonStats.pitcherStrikeouts.toString()),
              _statBox('与四球', p.seasonStats.pitcherWalks.toString()),
              _statBox('自責点', p.seasonStats.earnedRuns.toString()),
            ],
          )
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}

class BaseballFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    // Draw diamond
    Path path = Path();
    path.moveTo(size.width / 2, size.height - 40); // Home
    path.lineTo(size.width / 2 + 60, size.height - 100); // 1B
    path.lineTo(size.width / 2, size.height - 160); // 2B
    path.lineTo(size.width / 2 - 60, size.height - 100); // 3B
    path.close();
    canvas.drawPath(path, paint);
    
    // Draw outfield line
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width / 2, size.height - 40), radius: 180),
      3.14159 * 1.25, 3.14159 * 0.5, false, paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



class PitchVectorPainter extends CustomPainter {
  final List<Pitch> pitches;
  PitchVectorPainter(this.pitches);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 10);
    final radius = size.width / 2;

    final linePaint = Paint()..color = Colors.grey.shade400..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final platePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final plateBorderPaint = Paint()..color = Colors.grey.shade400..style = PaintingStyle.stroke..strokeWidth = 1.5;

    // Strike Zone
    Rect strikeZone = Rect.fromCenter(center: center, width: size.width * 0.45, height: size.height * 0.55);
    canvas.drawRect(strikeZone, linePaint);

    // Grid inside strike zone (3x3)
    double stepX = strikeZone.width / 3;
    double stepY = strikeZone.height / 3;
    for(int i = 1; i <= 2; i++) {
       canvas.drawLine(Offset(strikeZone.left + stepX * i, strikeZone.top), Offset(strikeZone.left + stepX * i, strikeZone.bottom), linePaint);
       canvas.drawLine(Offset(strikeZone.left, strikeZone.top + stepY * i), Offset(strikeZone.right, strikeZone.top + stepY * i), linePaint);
    }

    // Home plate (Pitcher's perspective: flat top, point at bottom)
    double plateTop = strikeZone.bottom + 15;
    double plateWidth = size.width * 0.45;
    Path platePath = Path();
    platePath.moveTo(center.dx - plateWidth/2, plateTop);
    platePath.lineTo(center.dx + plateWidth/2, plateTop);
    platePath.lineTo(center.dx + plateWidth/2, plateTop + 10);
    platePath.lineTo(center.dx, plateTop + 25);
    platePath.lineTo(center.dx - plateWidth/2, plateTop + 10);
    platePath.close();

    canvas.drawPath(platePath, platePaint);
    canvas.drawPath(platePath, plateBorderPaint);

    // Ball at center
    canvas.drawCircle(center, 4, Paint()..color = Colors.grey.shade800);

    // Draw arrows for each pitch
    for (var pitch in pitches) {
      if (pitch.ratio == 0 && pitch.breakLevel == 0) continue;
      
      // Calculate length based on breakLevel (0-100) and some base length
      double arrowLength = (pitch.breakLevel / 100.0) * (radius * 0.9);
      if (arrowLength < 10) arrowLength = 10; // minimum visibility
      
      // Angle: 0 is up. In math, 0 is right. We need to convert.
      // angle in degree: 0 = Up, 90 = Right, 180 = Down, 270 = Left
      double rad = pitch.angle * (pi / 180.0);
      
      final endPoint = Offset(
        center.dx + arrowLength * cos(rad),
        center.dy + arrowLength * sin(rad)
      );

      Color color = Colors.red;
      if (pitch.angle > 0 && pitch.angle < 90) color = Colors.blue;
      if (pitch.angle >= 90 && pitch.angle < 135) color = Colors.green;
      if (pitch.angle >= 135 && pitch.angle <= 180) color = Colors.purple;

      final arrowPaint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(center, endPoint, arrowPaint);

      // Draw arrow head
      double arrowHeadSize = 8;
      double arrowRad1 = rad + (pi * 0.8);
      double arrowRad2 = rad - (pi * 0.8);
      
      Path headPath = Path();
      headPath.moveTo(endPoint.dx, endPoint.dy);
      headPath.lineTo(
        endPoint.dx + arrowHeadSize * cos(arrowRad1),
        endPoint.dy + arrowHeadSize * sin(arrowRad1)
      );
      headPath.lineTo(
        endPoint.dx + arrowHeadSize * cos(arrowRad2),
        endPoint.dy + arrowHeadSize * sin(arrowRad2)
      );
      headPath.close();
      
      canvas.drawPath(headPath, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}




/// 選手の詳細を開く（閲覧用。他球団の選手も見られる）。
///  自球団の選手で allowActions のときだけ、練習メニュー・昇格／降格の操作を出す（試合中は出さない）
Future<void> showPlayerDetail(BuildContext context, dynamic appState, Player p, {bool allowActions = true, VoidCallback? onChanged}) {
  Team? mine;
  if (allowActions) {
    for (final t in (appState.teams as List<Team>)) {
      if (t.id == appState.myTeamId && t.players.any((x) => x.id == p.id)) mine = t;
    }
  }
  return showDialog(
    context: context,
    builder: (_) => PlayerDetailDialog(player: p, appState: appState, team: mine, isReadOnly: true, onRosterChanged: onChanged ?? () {}),
  );
}
