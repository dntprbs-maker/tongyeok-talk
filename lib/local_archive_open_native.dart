import 'package:sembast/sembast_io.dart';
import 'package:path_provider/path_provider.dart';

Future<Database> openArchiveDatabase() async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(
    '${directory.path}/tongyeok-history-v1.db',
  );
}
