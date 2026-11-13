#!/bin/bash
# flutter test を走らせ、flutter_tester を高性能コア（論理 0〜15）に固定して優先度を上げる。
#
# 理由：Windows（Intel のハイブリッド CPU）では、長い検証（数分〜）を裏で動かすと、数秒後に省電力コア（E コア）へ回されて
#       3〜5 倍遅くなることがある（バランス検証 tool/balance/* で確認）。短いテストでは要らない。
# 使い方：tool/ft.sh tool/balance/zz_balance_probe_test.dart --dart-define=DAYS=60
# 注意：マスク 0xFFFF は Core i7-14700F（P コア 8 個＝論理 16）の値。ほかの CPU では、P コアの論理プロセッサ数に合わせて変える（FT_MASK=0xFF など）。
MASK=${FT_MASK:-0xFFFF}
( for i in $(seq 1 2500); do
    powershell -NoProfile -c "Get-Process flutter_tester -ErrorAction SilentlyContinue | ForEach-Object { try { if (\$_.ProcessorAffinity -ne $MASK) { \$_.ProcessorAffinity = $MASK; \$_.PriorityClass = 'High' } } catch {} }" >/dev/null 2>&1
    sleep 2
  done ) &
WATCHER=$!
flutter test "$@" 2>&1
CODE=${PIPESTATUS[0]}
kill $WATCHER 2>/dev/null
exit $CODE
