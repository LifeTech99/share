import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class MbtilesService {
  static Future<String> copyMbtiles() async {
    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/newmap.mbtiles');

    if (!await file.exists()) {
      final data = await rootBundle.load(
        'assets/maps/newmap.mbtiles',
      );

      await file.writeAsBytes(
        data.buffer.asUint8List(),
      );
    }

    return file.path;
  }
  static Future<int> getTileCount() async {
  final path = await copyMbtiles();

  final db = await openDatabase(
    path,
    readOnly: true,
  );

  final result = await db.rawQuery(
    'SELECT COUNT(*) as count FROM tiles',
  );

  await db.close();

  return result.first['count'] as int;
}
static Future<String> getMbtilesPath() async {
  return await copyMbtiles();
}
}

