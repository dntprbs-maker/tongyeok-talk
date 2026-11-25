import 'package:sembast_web/sembast_web.dart';

Future<Database> openArchiveDatabase() =>
    databaseFactoryWeb.openDatabase('tongyeok-history-v1');
