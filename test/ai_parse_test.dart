import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/ai/ai_writer.dart';

void main() {
  const a = AiItem('a', 'player', ''), b = AiItem('b', 'player', '');
  test('区切りの揺れを読み取る', () {
    expect(AiPrompts.parse('===1===\nあ\n===2===\nい', [a, b]), {'a': 'あ', 'b': 'い'});
    expect(AiPrompts.parse('==========\n===ID: 1===\nあ\n===ID: 2===\nい\n', [a, b]), {'a': 'あ', 'b': 'い'});
    expect(AiPrompts.parse('===ID===\n1\n見出し\n\n本文', [a]), {'a': '見出し\n\n本文'});
    expect(AiPrompts.parse('見出し\n\n本文', [a]), {'a': '見出し\n\n本文'});
    expect(AiPrompts.parse('===ID===\nあ\n===ID===\nい', [a, b]), {'a': 'あ', 'b': 'い'});
  });
}
