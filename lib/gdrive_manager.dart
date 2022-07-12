import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart' as gsignin;
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:path_provider/path_provider.dart';

import 'google_auth_client.dart';

enum LoginState {
  notLoggedIn,
  initialisingLogin,
  fetchedFiles,
  loggedIn,
}

// Create a standard GoogleSignIn, with scope driveAppdataScope. This allows the
// modification of files for this app only in the drive.
gsignin.GoogleSignIn _googleSignIn = gsignin.GoogleSignIn.standard(
    scopes: <String>[gdrive.DriveApi.driveAppdataScope]);

class GoogleDriveManager extends ChangeNotifier {
  static final GoogleDriveManager _googleDriveManager =
      GoogleDriveManager._internal();

  factory GoogleDriveManager() {
    return _googleDriveManager;
  }

  GoogleDriveManager._internal();

  // The account, which may or may not be logged in.
  gsignin.GoogleSignInAccount? _account;

  // The drive API.
  gdrive.DriveApi? _driveApi;

  // The list of files from this app only in the drive.
  List<gdrive.File>? _files;

  // This bool is true when files are downloading or uploading and have yet to
  // complete.
  bool _busy = false;

  // The default file name for the file uploaded to drive.
  final String _defaultFileName = 'habits.json';

  // The FlutterSecureStorage for localModified time is handled in this class.
  final storage = const FlutterSecureStorage();

  // The default key for FlutterSecureStorage to store the localModifiedDate.
  final String _localModifiedStorageString = 'localModified';

  //
  DateTime? _localModifiedDate;

  // A stream for reacting to the login values.
  final StreamController<LoginState> _loginStateController =
      StreamController<LoginState>.broadcast();

  // LoginState _loginState = LoginState.notLoggedIn;

  gsignin.GoogleSignInAccount? get account => _account;
  bool get accountLoggedIn => _account != null;
  gdrive.DriveApi? get driveApi => _driveApi;
  List<gdrive.File>? get files => _files;
  String get defaultFileName => _defaultFileName;
  bool get busy => _busy;
  Stream<LoginState> get loginStateStream =>
      _loginStateController.stream.asBroadcastStream();
  DateTime? get localModifiedDate => _localModifiedDate;

  DateTime? get driveModifiedDate {
    if (_files != null && _files!.length == 1) {
      return _files!.first.modifiedTime;
    }
    return null;
  }

  Future<bool> init() async {
    String? str = await storage.read(key: _localModifiedStorageString);
    if (str != null) {
      _localModifiedDate = DateTime.parse(str);
    }
    // If an account was already logged in and the app is started, then it can
    // sign in silently without any further actions, triggering
    // _onCurrentUserChanged.
    try {
      gsignin.GoogleSignInAccount? acc = await _googleSignIn.signInSilently();
      if (acc != null) {
        // This is done separately to ensures the account full initialises
        // before the rest of the app is built.
        await _onCurrentUserChanged(acc);
      }
    } catch (e) {
      debugPrint('Could not sign in silently, $e');
    }

    _googleSignIn.onCurrentUserChanged
        .listen((gsignin.GoogleSignInAccount? acc) {
      _onCurrentUserChanged(acc);
    });
    return true;
  }

  Future<void> signIn() async {
    await _googleSignIn.signIn();
  }

  Future<void> signOut() async {
    await _googleSignIn.disconnect();
  }

  // This method is run whenever the current user is changed, either an
  // account is logged in or out.
  Future<void> _onCurrentUserChanged(
      gsignin.GoogleSignInAccount? account) async {
    _account = account;

    // If user signed out, make all properties null.
    if (account == null) {
      _driveApi = null;
      _files = null;
      updateLoginState(LoginState.notLoggedIn);
      notifyListeners();
      return;
    }

    // If an account logged in, set _driveApi using the account's authHeaders
    // and get the files in the account. Then notifyListeners.
    updateLoginState(LoginState.initialisingLogin);
    var authHeaders = await account.authHeaders;
    var authenticatedClient = GoogleAuthClient(authHeaders);
    var driveApi = gdrive.DriveApi(authenticatedClient);
    _driveApi = driveApi;
    _files = await _getDriveFiles(driveApi);
    print(_files?.length);
    if (_files == null || _files!.isEmpty) {
      await initJson();
    }
    updateLoginState(LoginState.fetchedFiles);
    updateLoginState(LoginState.loggedIn);
    notifyListeners();
  }

  initJson() async {
    print('INIT JSON\n\n\n');
    Map<String, dynamic> myJson = {"habit": []};
    var tmpDir = await getTemporaryDirectory();
    File file = File("${tmpDir.path}/$defaultFileName");
    if (file.existsSync()) {
      file.deleteSync();
    }
    file.createSync();
    file.writeAsStringSync(jsonEncode(myJson));
    await uploadFile(file);
  }

  Future<List<gdrive.File>?> _getDriveFiles(gdrive.DriveApi driveApi) async {
    var fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        $fields: 'files(name,id,mimeType,modifiedTime)');
    return fileList.files;
  }

  // Returns all files in drive with the same fileName.
  List<gdrive.File> findFiles(String fileName) {
    List<gdrive.File> foundFiles = [];
    if (_files == null) {
      return foundFiles;
    }

    for (var file in _files!) {
      if (file.name == fileName) {
        foundFiles.add(file);
      }
    }

    return foundFiles;
  }

  Future<void> addHabit(String habitName) async {
    if (_files == null || _files!.isEmpty) {
      return;
    }
    
  }

  Future<gdrive.File?> uploadFile(File file, {bool overwrite = true}) async {
    if (_driveApi == null) {
      throw ErrorHint('Not logged in to an account.');
    }

    _busy = true;
    notifyListeners();

    String tmpFileName = 'tmp_$_defaultFileName';

    gdrive.File fileToUpload = gdrive.File();
    fileToUpload.parents = ["appDataFolder"];
    if (_localModifiedDate != null) {
      fileToUpload.modifiedTime = _localModifiedDate;
    }
    fileToUpload.name = tmpFileName;

    for (var file in findFiles(tmpFileName)) {
      if (file.id != null) {
        await _driveApi!.files.delete(file.id!);
      }
    }

    var response = await _driveApi!.files.create(fileToUpload,
        uploadMedia: gdrive.Media(file.openRead(), file.lengthSync()));

    // If the overwrite parameter is true, then find all files in drive with the
    // same file name and deletes them before uploading the file.
    if (overwrite && fileToUpload.name != null) {
      for (var file in findFiles(_defaultFileName)) {
        if (file.id != null) {
          await _driveApi!.files.delete(file.id!);
        }
      }
      var newMetadata = gdrive.File();
      newMetadata.modifiedTime = fileToUpload.modifiedTime;
      newMetadata.name = _defaultFileName;
      await _driveApi!.files.update(
        newMetadata,
        response.id!,
      );
    }

    // for (var file in findFiles(tmpFileName)) {
    //   if (file.id != null) {
    //     await _driveApi!.files.delete(file.id!);
    //   }
    // }

    _files = await _getDriveFiles(_driveApi!);
    print(_files?.length);

    _busy = false;
    notifyListeners();
    return response;
  }

  // Downloads a file in drive, and returns the file downloaded.
  Future<void> downloadFile(
      BuildContext context, gdrive.File gdriveFile) async {
    if (_driveApi == null) {
      throw ErrorHint('Not signed in');
    }

    _busy = true;
    notifyListeners();

    // Since the DownloadOptions is set to fullMedial, as per the documentation,
    // the return type will be of type Media.
    gdrive.Media downloadFile = await _driveApi!.files.get(gdriveFile.id!,
        downloadOptions: gdrive.DownloadOptions.fullMedia) as gdrive.Media;

    final dir = await getExternalStorageDirectory();

    // Make saveFile in tmpDir and ensure it's blank.
    final saveFile = File('${dir?.path}/${gdriveFile.name}');
    if (saveFile.existsSync()) {
      saveFile.deleteSync();
    }
    saveFile.createSync();

    List<int> dataStore = [];

    // Listen to the Media's stream and when done, write the file to Temporary
    // Directory.
    downloadFile.stream.listen((data) {
      dataStore.insertAll(dataStore.length, data);
    }, onDone: () async {
      // Overwrites
      saveFile.writeAsBytesSync(dataStore);

      _busy = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint(e);
    });
  }

  Future<void> writeLocalModifiedDate({String? specificDateTimeString}) async {
    String date;
    if (specificDateTimeString != null) {
      date = specificDateTimeString;
    } else {
      String dateTimeNow = DateTime.now().toUtc().toString();

      // The date needs to be edited, because a file with a modifiedTime uploaded
      // to drive will be concatenated.
      String editedDate =
          '${dateTimeNow.substring(0, dateTimeNow.length - 4)}Z';
      date = editedDate;
    }
    await storage.write(key: _localModifiedStorageString, value: date);
    _localModifiedDate = DateTime.parse(date);

    notifyListeners();
    return;
  }

  Future<void> deleteLocalModifiedDate() async {
    await storage.delete(key: _localModifiedStorageString);
    notifyListeners();
    return;
  }

  void updateLoginState(LoginState state) {
    _loginStateController.sink.add(state);
  }

  void disposeStream() {
    _loginStateController.close();
  }
}
