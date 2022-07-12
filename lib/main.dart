import 'package:flutter/material.dart';
import 'package:test_upload_speed/gdrive_manager.dart';
import 'package:provider/provider.dart';

void main() async {
  runApp(ChangeNotifierProvider(
      create: (_) => GoogleDriveManager(), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: FutureBuilder(
          future: GoogleDriveManager().init(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return const MyHomePage();
          },
        ));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _controller = TextEditingController();

  _showAddDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              content: TextField(controller: _controller),
              actions: [
                TextButton(
                  child: Text('Confirm'),
                  onPressed: () async {
                    await GoogleDriveManager().addHabit(_controller.text);
                    Navigator.of(context).pop();
                  },
                )
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Consumer<GoogleDriveManager>(
        builder: (context, manager, child) => Column(
          children: [
            Text(manager.account?.displayName ?? 'Not Logged In'),
            TextButton(
                onPressed: () {
                  manager.accountLoggedIn
                      ? manager.signOut()
                      : manager.signIn();
                },
                child: Text(manager.accountLoggedIn ? ' Log out' : ' Log in')),
            !manager.accountLoggedIn
                ? Container()
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: manager.files?.length,
                    itemBuilder: (context, index) =>
                        ListTile(title: Text(manager.files![index].name!)),
                  ),
            IconButton(
              icon: Icon(Icons.add),
              onPressed: () => _showAddDialog(),
            ),
          ],
        ),
      )),
    );
  }
}
