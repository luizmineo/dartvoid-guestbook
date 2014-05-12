import 'dart:io';
import 'dart:async';

import 'package:redstone/server.dart' as app;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:di/di.dart';
import 'package:logging/logging.dart';

var logger = new Logger("guestbook");

class DbConnManager {

  String uri;

  DbConnManager(String this.uri);

  Future<Db> connect() {
    Db conn = new Db(uri);
    return conn.open().then((_) => conn);
  }

  void close(Db conn) {
    conn.close();
  }

}

@app.Interceptor(r'/.+')
createConn(DbConnManager connManager) {
  connManager.connect().then((Db dbConn) {
    app.request.attributes['dbConn'] = dbConn;
    app.chain.next(() => connManager.close(dbConn));
  }).catchError((e) {
    app.chain.interrupt(statusCode: HttpStatus.INTERNAL_SERVER_ERROR, 
        response: {"error": "DATABASE_UNAVAILABLE"});
  });
}

@app.Group("/posts")
class Post {

  final String collectionName = "posts";

  @app.Route('/list')
  list(@app.Attr() Db dbConn) {
    logger.info("Guestbook : list posts");

    var coll = dbConn.collection(collectionName);
    return coll.find().toList().then((data) {
      logger.info("Got ${data.length} post(s)");
      logger.info("${data}");
      return data;
    }).catchError((e) {
      logger.warning("Unable to get post(s): ${e}");
      return [];
    });

  }

  @app.Route('/add', methods: const [app.POST])
  add(@app.Attr() Db dbConn, @app.Body(app.JSON) Map post) {
    logger.info("Guestbook : add post");

    var coll = dbConn.collection(collectionName);
    return coll.insert({"name": post["name"], "message": post["message"]}).then((data) {
      logger.info("Added post: $post");
      logger.info("${data}");
      return "Added post: $post";
    }).catchError((e) {
      logger.warning("Unable to save post: ${e}");
      return "Unable to save post";
    });
  }

  @app.Route('/delete', methods: const [app.DELETE])
  delete(@app.Attr() Db dbConn) {
    logger.info("Guestbook : delete post");

    var coll = dbConn.collection(collectionName);
    return coll.remove().then((data) {
      logger.info("Removed ${data["n"]} posts");
      logger.info("${data}");
      return "Removed ${data["n"]} posts";
    }).catchError((e) {
      logger.warning("Unable to delete posts: ${e}");
      return "Unable to delete posts";
    });
  }

}

main() {

  app.setupConsoleLog();

  var dbUri = Platform.environment['MONGODB_URI'];
  if (dbUri == null) {
    dbUri = "mongodb://localhost/guestbook";
  }

  app.addModule(new Module()
      ..bind(DbConnManager, toValue: new DbConnManager(dbUri)));

  var portEnv = Platform.environment['PORT'];

  app.start(address: '127.0.0.1', 
            port: portEnv != null ? int.parse(portEnv) : 8080, 
            staticDir: null);

}