import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TileDownloader {

  static Future<void> downloadTile({
    required int zoom,
    required int x,
    required int y,
  }) async {

    final url =
        "https://tile.openstreetmap.org/$zoom/$x/$y.png";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {

      final dir =
          await getApplicationDocumentsDirectory();

      final folder = Directory(
        "${dir.path}/tiles/$zoom/$x",
      );

      if (!folder.existsSync()) {
        folder.createSync(recursive: true);
      }

      final file =
          File("${folder.path}/$y.png");

      await file.writeAsBytes(response.bodyBytes);

      print("Saved $zoom/$x/$y");
    }
  }
}