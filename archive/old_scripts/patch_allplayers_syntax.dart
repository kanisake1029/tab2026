import 'dart:io';

void main() {
  File f = File('lib/screens/order_tabs/all_players_tab.dart');
  String text = f.readAsStringSync();
  
  String search = '''                },
              );
        ),
      ],
    );''';
    
  String replace = '''                },
              ),
        ),
      ],
    );''';
    
  text = text.replaceAll(search, replace);
  f.writeAsStringSync(text);
  print('Fixed syntax error in all_players_tab.dart');
}
