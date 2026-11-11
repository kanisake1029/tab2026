import 'dart:io';

void main() {
  File f = File('lib/providers/app_state.dart');
  String text = f.readAsStringSync();
  
  text = text.replaceAll("繧ｹ繝ｩ繧､繝€繝ｼ", "スライダー");
  text = text.replaceAll("繧ｹ繝医Ξ繝ｼ繝・", "ストレート");
  text = text.replaceAll("繧ｫ繝ｼ繝・", "カーブ");
  text = text.replaceAll("繝輔か繝ｼ繧ｯ", "フォーク");

  f.writeAsStringSync(text);
  
  File p = File('lib/models/player.dart');
  String pText = p.readAsStringSync();
  pText = pText.replaceAll("繧ｹ繝ｩ繧､繝€繝ｼ", "スライダー");
  pText = pText.replaceAll("繧ｹ繝医Ξ繝ｼ繝・", "ストレート");
  pText = pText.replaceAll("繧ｫ繝ｼ繝・", "カーブ");
  pText = pText.replaceAll("繝輔か繝ｼ繧ｯ", "フォーク");
  p.writeAsStringSync(pText);
}
