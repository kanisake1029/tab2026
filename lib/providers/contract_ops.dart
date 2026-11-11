part of 'app_state.dart';

/// 契約更改（自球団・11月）：年俸を50万円単位、1〜12年で提示する（何度でも）。信頼が低い選手に大きな減俸を出すと退団することがある。
///  ほかに、コーチ・スカウトへの転任、引退勧告、自由契約を打診できる。12月1日に、まだの選手は希望額で更改する
extension ContractOps on AppState {
  /// 契約更改の期間（11月）
  bool get renewalOpen => currentDate.month == 11;

  /// 今年の更改が済んだか
  bool renewalDone(Player p) => renewSigned.contains(p.id);

  /// 複数年契約の途中（今年は更改しない）
  bool inMultiYear(Player p) => p.contractYears > 1 && !renewSigned.contains(p.id);

  /// 選手の希望額（50万円単位）。信頼が低いほど高めに言う
  int renewAsk(Player p) {
    final t = TransferEngine.renewTarget(p);
    final a = t * (1 + (50 - p.trust).clamp(-20, 40) / 250);
    return max(p.ikusei ? 250 : 450, (a / 50).round() * 50);
  }

  /// 年数による希望額の変わり方：ベテラン（30歳〜）は長い契約なら少し下げてよい。若手は長い契約には上乗せを求める
  int renewAskFor(Player p, int years) {
    final ask = renewAsk(p);
    final per = p.age >= 30 ? -0.025 : (p.age <= 26 ? 0.03 : 0.0);
    return max(p.ikusei ? 250 : 450, (ask * (1 + per * (years - 1)) / 50).round() * 50);
  }

  /// 提示する。戻り値：結果の文
  String offerRenewal(Player p, int salary, int years) {
    final my = myTeam;
    if (my == null || !my.players.contains(p)) return '自球団の選手ではありません';
    if (!renewalOpen) return '契約更改は11月です';
    if (renewSigned.contains(p.id)) return 'もう更改が済んでいます';
    salary = (salary / 50).round() * 50;
    years = years.clamp(1, 12);
    final need = renewAskFor(p, years);
    final tries = (renewTries[p.id] ?? 0) + 1;
    renewTries[p.id] = tries;
    final r = Random(p.id.hashCode ^ tries ^ currentDate.day);
    if (salary >= need) {
      final old = p.salary;
      p.prevSalary = old;
      p.salary = salary;
      p.contractYears = years;
      renewSigned.add(p.id);
      if (salary > need * 1.1) p.trust = (p.trust + 3).clamp(0, 100);
      transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 契約更改 ${formatSalary(old)}→${formatSalary(salary)}${years > 1 ? '（$years年契約）' : ''}');
      updateAndSave();
      return '${p.registeredName}は${formatSalary(salary)}${years > 1 ? '・$years年' : ''}で契約しました';
    }
    // 保留：信頼が下がる。信頼が低く、大きな減俸なら退団することがある
    p.trust = (p.trust - 2 - (tries > 2 ? 2 : 0)).clamp(0, 100);
    final cut = 1 - salary / max(1, p.salary);
    if (cut > 0.25 && p.trust < 40) {
      final chance = ((cut - 0.25) * 1.6 + (40 - p.trust) / 80 + (tries - 1) * 0.05).clamp(0.0, 0.85);
      if (r.nextDouble() < chance) {
        RosterEngine.removePlayer(my, p);
        freeAgents.add(FreeAgent(p, my.id, '交渉決裂'));
        transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 契約交渉が決裂し退団');
        _addNews(['${p.registeredName}は契約更改で合意できず、退団しました（自由契約）']);
        updateAndSave();
        return '${p.registeredName}は提示に納得せず、退団しました（自由契約）';
      }
    }
    updateAndSave();
    return '${p.registeredName}は保留しました（希望は${formatSalary(need)}${years > 1 ? '・$years年' : ''}くらい。信頼 ${p.trust}）';
  }

  /// まだの選手をまとめて希望額（1年）で更改する
  int renewAllAtAsk() {
    final my = myTeam;
    if (my == null || !renewalOpen) return 0;
    var n = 0;
    for (final p in List.of(my.players)) {
      if (renewSigned.contains(p.id) || inMultiYear(p) || p.draftYear == currentDate.year) continue;
      offerRenewal(p, renewAskFor(p, 1), 1);
      n++;
    }
    return n;
  }

  /// コーチ・スカウトへの転任を打診する（受ければ引退して、その役職に就く）
  String offerStaffRole(Player p, String role) {
    final my = myTeam;
    if (my == null || !my.players.contains(p)) return '自球団の選手ではありません';
    final r = Random(p.id.hashCode ^ role.hashCode ^ currentDate.day);
    final chance = ((p.age >= 34 ? 0.8 : (p.age >= 31 ? 0.5 : (p.age >= 28 ? 0.2 : 0.05))) + (p.trust - 50) / 100 - (p.ovr >= 70 ? 0.25 : 0)).clamp(0.02, 0.95);
    if (r.nextDouble() >= chance) {
      p.trust = (p.trust - 5).clamp(0, 100);
      updateAndSave();
      return '${p.registeredName}は「まだ現役を続けたい」と断りました（信頼 ${p.trust}）';
    }
    RosterEngine.removePlayer(my, p);
    _keepRetiree(p, my, currentDate.year);
    final c = TransferEngine.obFromPlayer(p, my.id, r);
    coaches.add(c);
    hireCoach(my, role, c);
    transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 現役引退・$roleに就任');
    _addNews(['${p.registeredName}が現役を引退し、$roleに就任しました']);
    updateAndSave();
    return '${p.registeredName}は現役を引退し、$roleに就任しました';
  }

  /// 引退勧告：受ければ引退（OB 一覧へ）。断ったとき、信頼が低ければ退団（自由契約）
  String adviseRetire(Player p) {
    final my = myTeam;
    if (my == null || !my.players.contains(p)) return '自球団の選手ではありません';
    final r = Random(p.id.hashCode ^ 0x7e ^ currentDate.day);
    final chance = ((p.age >= 36 ? 0.85 : (p.age >= 33 ? 0.6 : (p.age >= 30 ? 0.3 : 0.08))) + (p.trust - 50) / 120 - (p.ovr >= 65 ? 0.2 : 0)).clamp(0.02, 0.95);
    if (r.nextDouble() < chance) {
      RosterEngine.removePlayer(my, p);
      _keepRetiree(p, my, currentDate.year);
      if (!p.foreignSlot) coaches.add(TransferEngine.obFromPlayer(p, my.id, r));
      transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName}（${p.age}歳）引退');
      _addNews(['${p.registeredName}が引退を決めました']);
      updateAndSave();
      return '${p.registeredName}は引退を受け入れました';
    }
    p.trust = (p.trust - 8).clamp(0, 100);
    if (p.trust < 35) {
      RosterEngine.removePlayer(my, p);
      freeAgents.add(FreeAgent(p, my.id, '退団'));
      transactions.insert(0, '${_today()} ${teamShort(my)} ${p.registeredName} 引退勧告を拒んで退団');
      _addNews(['${p.registeredName}は引退勧告を拒み、退団しました（他球団で現役を続けます）']);
      updateAndSave();
      return '${p.registeredName}は引退を拒み、退団しました（自由契約）';
    }
    updateAndSave();
    return '${p.registeredName}は「まだやれる」と引退を断りました（信頼 ${p.trust}）';
  }
}
