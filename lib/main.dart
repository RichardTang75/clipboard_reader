import 'package:clipboard_reader/clipboardtranslate.dart';
import 'package:clipboard_reader/textproperties.dart';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

// TODO: Multiple definitions - using tabs
// TODO: Persistent scrollbar
// TODO: Settings page
// TODO: Ignore definitions, cache definitions
// TODO: Fancy pinyin

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class StandardCard extends Card {
  // optional title, subtitle, body
  StandardCard(
      {super.key,
      required BuildContext context,
      String? title,
      TextStyle? titleStyle,
      String? subtitle,
      TextStyle? subtitleStyle,
      String? body,
      TextStyle? bodyStyle,
      AlignmentGeometry? bodyAlignment,
      double? bodySize})
      : super(
          child: Column(
            children: [
              if (title != null)
                ListTile(
                  title: Text(
                    title,
                    style:
                        titleStyle ?? Theme.of(context).textTheme.headlineLarge,
                  ),
                  subtitle: subtitle != null
                      ? Text(
                          subtitle,
                          style: subtitleStyle ??
                              Theme.of(context).textTheme.titleLarge,
                        )
                      : null,
                ),
              if (body != null)
                LimitedBox(
                  maxHeight: bodySize ?? double.infinity,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(TextProperties.padding,
                          0, TextProperties.padding, TextProperties.padding),
                      child: Align(
                        alignment: bodyAlignment ?? Alignment.center,
                        child: Text(
                          body,
                          style: bodyStyle ??
                              Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.green,
        textTheme: Theme.of(context).textTheme.apply(
              fontSizeFactor: TextProperties.fontSizeFactor,
            ),
      ),
      home: const MyHomePage(title: 'Chinese Clipboard Reader'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var clipboardReader = ClipboardReader();
  @override
  void initState() {
    super.initState();
    clipboardReader.startTimer();
  }

  String _clipboardText = 'fa';
  List<Map<String, dynamic>> _translatedText = [];
  final _scrollController = ScrollController();

  // build this widget when clipboardReader.clipboardText changes
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clipboardReader.addListener(() {
      setState(() {
        _clipboardText = clipboardReader.clipboardText;
        _translatedText = clipboardReader.translatedText;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    final style = Theme.of(context).textTheme.headlineLarge;
    final line_height = style!.fontSize! * TextProperties.fontSizeFactor;
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        child: SelectableRegion(
          selectionControls: materialTextSelectionControls,
          focusNode: FocusNode(),
          child: Column(
            // Column is also a layout widget. It takes a list of children and
            // arranges them vertically. By default, it sizes itself to fit its
            // children horizontally, and tries to be as tall as its parent.
            //
            // Invoke "debug painting" (press "p" in the console, choose the
            // "Toggle Debug Paint" action from the Flutter Inspector in Android
            // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
            // to see the wireframe for each widget.
            //
            // Column has various properties to control how it sizes itself and
            // how it positions its children. Here we use mainAxisAlignment to
            // center the children vertically; the main axis here is the vertical
            // axis because Columns are vertical (the cross axis would be
            // horizontal).
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              StandardCard(
                context: context,
                title: 'Clipboard',
                titleStyle: Theme.of(context).textTheme.titleLarge,
                body: _clipboardText,
                bodyStyle: Theme.of(context).textTheme.headlineMedium,
                bodyAlignment: Alignment.centerLeft,
                bodySize: line_height * 3,
              ),
              Expanded(
                child: AlignedGridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  itemCount: _translatedText.length,
                  itemBuilder: (context, index) {
                    return StandardCard(
                      context: context,
                      title: _translatedText[index]['showBoth']!
                          ? '${_translatedText[index]['simplified']!} | ${_translatedText[index]['traditional']!}'
                          : _translatedText[index]['simplified']!,
                      titleStyle: Theme.of(context).textTheme.headlineLarge,
                      subtitle: _translatedText[index]['pinyin']!,
                      subtitleStyle: Theme.of(context).textTheme.titleLarge,
                      body: _translatedText[index]['english']!,
                      bodyStyle: Theme.of(context).textTheme.titleLarge,
                      bodySize: line_height * 2,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
