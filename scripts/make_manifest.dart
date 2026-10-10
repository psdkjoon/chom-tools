import 'dart:convert';
import 'dart:io';

import 'sha256.dart';

const abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

Future<String> digest(File file) async {
  final hash = Sha256();
  await for (final chunk in file.openRead()) {
    hash.add(chunk);
  }
  return hash.close();
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run scripts/make_manifest.dart <owner/repo> <tag>');
    exit(64);
  }
  final base = 'https://github.com/${args[0]}/releases/download/${args[1]}';
  final files = Directory('tools')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final tools = <Map<String, Object?>>[];
  for (final file in files) {
    final meta = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final id = meta['id'] as String;
    final version = meta['version'] as String;
    final assets = <String, Object?>{};
    for (final abi in abis) {
      for (final ext in ['.tar.gz', '']) {
        final name = '$id-$version-$abi$ext';
        final asset = File('dist/$name');
        if (!asset.existsSync()) continue;
        assets[abi] = {
          'url': '$base/$name',
          'sha256': await digest(asset),
          'size': asset.lengthSync(),
          'archive': ext.isEmpty ? 'none' : 'tar.gz',
        };
        break;
      }
    }
    if (assets.isEmpty) {
      stderr.writeln('skipping $id: no assets in dist/');
      continue;
    }
    meta['assets'] = assets;
    tools.add(meta);
  }

  await File('dist/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({'schema': 1, 'tools': tools}),
  );
  stdout.writeln('${tools.length} tools written to dist/manifest.json');
}
