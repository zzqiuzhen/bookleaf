import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  final ReaderSettings reader = ReaderSettings();
  bool _loaded = false;
  File? _file;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/BookLeaf');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _file = File('${dir.path}/settings.json');
      if (_file!.existsSync()) {
        final map = jsonDecode(await _file!.readAsString());
        if (map is Map<String, dynamic>) reader.applyJson(map);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _file?.writeAsString(jsonEncode(reader.toJson()));
    } catch (_) {}
  }

  void update(void Function(ReaderSettings s) change) {
    change(reader);
    _persist();
    notifyListeners();
  }
}
