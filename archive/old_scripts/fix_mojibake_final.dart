import 'dart:io';

void replaceInFile(String path, Map<String, String> replacements) {
  File f = File(path);
  if (!f.existsSync()) return;
  String text = f.readAsStringSync();
  bool changed = false;
  for (var entry in replacements.entries) {
    if (text.contains(entry.key)) {
      text = text.replaceAll(entry.key, entry.value);
      changed = true;
    }
  }
  if (changed) {
    f.writeAsStringSync(text);
    print('Updated \$path');
  }
}

void main() {
  Map<String, String> m = {
    '繧ｹ繝ｩ繧､繝€繝ｼ': 'スライダー',
    '繧ｹ繝医Ξ繝ｼ繝・': 'ストレート',
    '繧ｫ繝ｼ繝・': 'カーブ',
    '繝輔か繝ｼ繧ｯ': 'フォーク',
    '縲・': '【',
    '笆ｶ': '▶',
    '謇捺茶': '打撃',
    '繝輔ぃ繧ｦ繝ｫ繝輔Λ繧､': 'ファウルフライ',
    '繝輔Λ繧､繧｢繧ｦ繝・': 'フライアウト',
    '繝輔Λ繧､': 'フライ',
    '繝輔ぃ繧ｦ繝ｫ': 'ファウル',
    '逅・岼': '球目',
    '謌千ｸｾ繝・・繧ｿ縺後≠繧翫∪縺帙ｓ': '成績データがありません',
    '蜈域判 (Away) 謇捺茶謌千ｸｾ': '先攻 (Away) 打撃成績',
    '蠕梧判 (Home) 謇捺茶謌千ｸｾ': '後攻 (Home) 打撃成績',
    '蜈域判 (Away) 謚墓焔謌千ｸｾ': '先攻 (Away) 投手成績',
    '蠕梧判 (Home) 謚墓焔謌千ｸｾ': '後攻 (Home) 投手成績',
    '1謇灘ｸｭ縺斐→': '1打席ごと',
    '1逅・＃縺ｨ (隧ｳ邏ｰ)': '1球ごと (詳細)',
    '謇捺茶謌千ｸｾ': '打撃成績',
    '謚墓焔謌千ｸｾ': '投手成績',
    '縺翫∪縺九○': 'おまかせ',
    '譌･譛ｬ': '日本',
    '謚墓焔': '投手',
    '謐墓焔': '捕手',
    '荳€蝪∵焔': '一塁手',
    '莠悟｡∵焔': '二塁手',
    '荳牙｡∵焔': '三塁手',
    '驕頑茶謇・': '遊撃手',
    '蟾ｦ鄙ｼ謇・': '左翼手',
    '荳ｭ蝣・焔': '中堅手',
    '蜿ｳ鄙ｼ謇・': '右翼手',
    '謇捺茶(菴ｵ谿ｺ)': '打撃(併殺)',
    '菴ｵ谿ｺ謇・': '併殺打',
    '隕区逃縺励Ο謖ｯ': '見逃し三振',
    '遨ｺ謖ｯ繧顔二謖ｯ': '空振り三振',
    '蝗幄逅・': '四球',
    '謇捺茶(繝偵ャ繝・)': '打撃(ヒット)',
    '謇捺茶(莠悟｡∵桶)': '打撃(二塁打)',
    '謇捺茶(荳牙｡∵桶)': '打撃(三塁打)',
    '謇捺茶(譛ｬ蝨∵桶)': '打撃(本塁打)',
    '蜊倡打': '単打',
    '莠悟｡∵桶': '二塁打',
    '荳牙｡∵桶': '三塁打',
    '譛ｬ蝨∵桶': '本塁打',
  };
  
  replaceInFile('lib/providers/app_state.dart', m);
  replaceInFile('lib/models/player.dart', m);
  replaceInFile('lib/engine/match_simulator.dart', m);
  replaceInFile('lib/screens/schedule_screen.dart', m);
  replaceInFile('lib/utils/data_generator.dart', m);
}
