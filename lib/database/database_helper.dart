import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:latlong2/latlong.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Map<String, Object?>?> getGeofence() async {
    final db = await database;

    final result = await db.query('geofence', limit: 1);

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<List<LatLng>> getGeofencePoints(int geofenceId) async {
    final db = await database;

    final result = await db.query(
      'geofence_points',
      where: 'geofence_id = ?',
      whereArgs: [geofenceId],
      orderBy: 'point_order ASC',
    );

    return result.map((row) {
      return LatLng(row['latitude'] as double, row['longitude'] as double);
    }).toList();
  }

  Future<void> deleteAllGeofences() async {
    final db = await database;

    // Delete points first because they reference geofence
    await db.delete('geofence_points');

    // Then delete the geofence
    await db.delete('geofence');
  }

  Future<int> insertGeofence({
    required String name,
    required List<LatLng> points,
  }) async {
    final db = await database;
    await deleteAllGeofences();

    // Insert the geofence
    int geofenceId = await db.insert('geofence', {'name': name});

    // Insert each point
    for (int i = 0; i < points.length; i++) {
      await db.insert('geofence_points', {
        'geofence_id': geofenceId,
        'latitude': points[i].latitude,
        'longitude': points[i].longitude,
        'point_order': i,
      });
    }

    return geofenceId;
  }

  Future<void> insertLog(
    String type,
    String message,
    DateTime timestamp,
  ) async {
    final db = await database;
    await db.insert('logs', {
      'type': type,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> getLogs() async {
    final db = await database;
    return await db.query('logs', orderBy: 'timestamp DESC');
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'livestock.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE geofence (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE geofence_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        geofence_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        point_order INTEGER NOT NULL,
        FOREIGN KEY (geofence_id) REFERENCES geofence(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          message TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
    }
  }
}
