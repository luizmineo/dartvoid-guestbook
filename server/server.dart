import 'dart:io';
import 'dart:async';

import 'package:redstone/server.dart' as app;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:connection_pool/connection_pool.dart';
import 'package:di/di.dart';
import 'package:logging/logging.dart';

var logger = new Logger("guestbook");

class MongoDbPool extends ConnectionPool<Db> {

  String uri;

  MongoDbPool(String this.uri, int poolSize) : super(poolSize);

  @override
  void closeConnection(Db conn) {
    conn.close();
  }

  @override
  Future<Db> openNewConnection() {
    var conn = new Db(uri);
    return conn.open().then((_) => conn);
  }
}

@app.Interceptor(r'/services/.+')
dbInterceptor(MongoDbPool pool) {
  pool.getConnection().then((managedConnection) {
    app.request.attributes["conn"] = managedConnection.conn;
    app.chain.next(() {
      if (app.chain.error is ConnectionException) {
        pool.releaseConnection(managedConnection, markAsInvalid: true);
      } else {
        pool.releaseConnection(managedConnection);
      }
    });
  });
}

@app.Group("/posts")
class Post {

  final String collectionName = "posts";

  @app.Route('/list')
  list(@app.Attr() Db conn) {
    logger.info("Guestbook : list posts");

    var coll = conn.collection(collectionName);
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
  add(@app.Attr() Db conn, @app.Body(app.JSON) Map post) {
    logger.info("Guestbook : add post");

    var coll = conn.collection(collectionName);
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
  delete(@app.Attr() Db conn) {
    logger.info("Guestbook : delete post");

    var coll = conn.collection(collectionName);
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

  var poolSize = 3;

  app.addModule(new Module()
      ..bind(MongoDbPool, toValue: new MongoDbPool(dbUri, poolSize)));

  var portEnv = Platform.environment['PORT'];

  app.start(address: '127.0.0.1', 
            port: portEnv != null ? int.parse(portEnv) : 8080);

}