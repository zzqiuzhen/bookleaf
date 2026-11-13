import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/library_store.dart';

Future<void> pickAndImportBooks(
  BuildContext context,
  LibraryStore store, {
  void Function(int count, String? error)? onDone,
}) async {
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(
      type: FileType.any,
    );
  } catch (e) {
    onDone?.call(0, '无法打开文件选择器：$e');
    return;
  }
  final picked = files.where((f) {
    final name = f.name.toLowerCase();
    return (name.endsWith('.epub') || name.endsWith('.txt')) && f.path != null;
  }).toList();
  if (picked.isEmpty) {
    onDone?.call(0, '没有可导入的 EPUB / TXT 文件');
    return;
  }

  var ok = 0;
  final errors = <String>[];
  if (!context.mounted) return;
  showCupertinoDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CupertinoAlertDialog(
      title: Text('正在导入'),
      content: Padding(
        padding: EdgeInsets.only(top: 14),
        child: CupertinoActivityIndicator(radius: 14),
      ),
    ),
  );
  for (final f in picked) {
    try {
      await store.importFile(f.path!, f.name);
      ok++;
    } on ImportException catch (e) {
      errors.add('${f.name}：${e.message}');
    } catch (e) {
      errors.add('${f.name}：$e');
    }
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  onDone?.call(ok, errors.isEmpty ? null : errors.join('\n'));
}

void showImportResult(BuildContext context, int count, String? error) {
  if (count == 0 && error == null) return;
  showCupertinoDialog(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(error == null ? '导入完成' : '导入结果'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          error == null
              ? '已添加 $count 本书'
              : (count > 0 ? '成功 $count 本\n$error' : error),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

/// Small helper used from multiple places: import with UI feedback.
Future<void> importWithFeedback(BuildContext context, LibraryStore store) async {
  await pickAndImportBooks(context, store, onDone: (count, error) {
    if (context.mounted) showImportResult(context, count, error);
  });
}
