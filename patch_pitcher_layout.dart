import 'dart:io';

void main() {
  File f = File('lib/screens/order_tabs/pitcher_tab.dart');
  String text = f.readAsStringSync();
  
  text = text.replaceAll('flex: 5,', 'flex: 1,');
  text = text.replaceAll('flex: 4,', 'flex: 1,');
  
  String searchRow = '''                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DropdownButton<String>(''';
  String replaceWrap = '''                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(''';
  text = text.replaceAll(searchRow, replaceWrap);
  
  String searchInnerRow = '''                          Row(
                            children: [
                              buildCyberText('ダブルクローザー', size: 14, glow: false),''';
  String replaceInnerRow = '''                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              buildCyberText('ダブルクローザー', size: 14, glow: false),''';
  text = text.replaceAll(searchInnerRow, replaceInnerRow);
  
  f.writeAsStringSync(text);
  print('Fixed PitcherTab!');
}
