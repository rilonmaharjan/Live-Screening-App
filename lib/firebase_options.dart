import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Configured for `live-screening-app`
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBxeY-w0am3oR8J6i481l-pTy0odIZx2a0',
    appId: '1:673232481067:web:a915fae0d0c1b6a0a3b36e',
    messagingSenderId: '673232481067',
    projectId: 'live-screening-app',
    authDomain: 'live-screening-app.firebaseapp.com',
    storageBucket: 'live-screening-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCLL3OITsqhvXoBfwQUcFQEtaCoiribE7w',
    appId: '1:673232481067:android:977aa2802bf73958a3b36e',
    messagingSenderId: '673232481067',
    projectId: 'live-screening-app',
    storageBucket: 'live-screening-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBxeY-w0am3oR8J6i481l-pTy0odIZx2a0',
    appId: '1:673232481067:web:a915fae0d0c1b6a0a3b36e',
    messagingSenderId: '673232481067',
    projectId: 'live-screening-app',
    storageBucket: 'live-screening-app.firebasestorage.app',
    iosBundleId: 'com.example.rndscreeningap',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBxeY-w0am3oR8J6i481l-pTy0odIZx2a0',
    appId: '1:673232481067:web:a915fae0d0c1b6a0a3b36e',
    messagingSenderId: '673232481067',
    projectId: 'live-screening-app',
    storageBucket: 'live-screening-app.firebasestorage.app',
    iosBundleId: 'com.example.rndscreeningap',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBxeY-w0am3oR8J6i481l-pTy0odIZx2a0',
    appId: '1:673232481067:web:a915fae0d0c1b6a0a3b36e',
    messagingSenderId: '673232481067',
    projectId: 'live-screening-app',
    authDomain: 'live-screening-app.firebaseapp.com',
    storageBucket: 'live-screening-app.firebasestorage.app',
  );
}
