# 失敗したときに理由をファイルに残して実行する：blender -b --python run.py -- <script.py> <出力フォルダ> ...
import sys, os, traceback
args = sys.argv[sys.argv.index('--') + 1:]
script, out = args[0], args[1]
sys.argv = [sys.argv[0], '--'] + args[1:]
try:
    exec(compile(open(script, encoding='utf8').read(), script, 'exec'), {'__name__': '__main__', '__file__': script})
except Exception:
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'error.txt'), 'w', encoding='utf8').write(traceback.format_exc())
