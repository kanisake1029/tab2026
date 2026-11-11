import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
// flutter_scene:init:start
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    // いまは 3D の素材ファイル（.glb・.fmat）を使わないので、フォルダを探さない（探すとプロジェクト全体を依存に入れてビルドが止まる）
    buildScenes(buildInput: input, buildOutput: output, inputFilePaths: const []);
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output, materials: const []);
// flutter_scene:init:end
  });
}
