import 'dart:math';
import 'package:flutter/material.dart';
import 'package:clipboard/clipboard.dart';
import 'dart:async';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

// TODO: Persistent scrollbar
// TODO: Multiple definitions - using tabs
// TODO: Settings page
// TODO: Ignore definitions, cache definitions

// Python
// TODO: Fancy pinyin
// TODO: Variant character, multiple definitions

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class TextProperties {
  static const double padding = 16;
  static const double fontSizeFactor = 1.1;
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

class ClipboardReader extends ChangeNotifier {
  String _clipboardText = '';
  String get clipboardText => _clipboardText;
  List<Map<String, dynamic>> _translatedText = [];
  List<Map<String, dynamic>> get translatedText => _translatedText;

  static const Map<String, List<int>> ranges = {
    'CJK Unified Ideographs': [0x4E00, 0x9FFF],
    'CJK Unified Ideographs Extension A': [0x3400, 0x4DBF],
    'CJK Unified Ideographs Extension B': [0x20000, 0x2A6DF],
    'CJK Unified Ideographs Extension C': [0x2A700, 0x2B73F],
    'CJK Unified Ideographs Extension D': [0x2B740, 0x2B81F],
    'CJK Unified Ideographs Extension E': [0x2B820, 0x2CEAF],
    'CJK Unified Ideographs Extension F': [0x2CEB0, 0x2EBEF],
    'CJK Compatibility Ideographs': [0xF900, 0xFAFF],
    'CJK Compatibility Ideographs Supplement': [0x2F800, 0x2FA1F],
  };

  bool isChinese(String s) {
    int codeUnit = s.codeUnitAt(0);
    for (var range in ranges.values) {
      if (codeUnit >= range[0] && codeUnit <= range[1]) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> lookupExactMatch(db, String search) {
    final stmt = db.prepare(
        "SELECT Simplified, Traditional, Pinyin, English FROM cedict_lookup INNER JOIN cedict ON cedict_lookup.cedict_id = cedict.id WHERE lookup = '$search'");
    final lookupResult = stmt.select();
    if (lookupResult.isNotEmpty) {
      final row = lookupResult.first;
      final simplified = row['Simplified'];
      final traditional = row['Traditional'];
      final pinyin = row['Pinyin'];
      final english = row['English'];
      bool showBoth = simplified != traditional;
      return {
        'simplified': simplified,
        'traditional': traditional,
        'pinyin': pinyin,
        'english': english,
        'showBoth': showBoth
      };
    } else {
      return {};
    }
  }

  int lookaheadAndTranslate(
      int i, int minLookAhead, int maxLookahead, String text, db) {
    if (i + minLookAhead > text.length) {
      return 0;
    }
    maxLookahead = min(maxLookahead, text.length - i);
    final lookahead = text.substring(i, i + minLookAhead);
    final stmt = db.prepare(
        "SELECT LENGTH(lookup) AS length_of_longest_match FROM cedict_lookup WHERE lookup LIKE '$lookahead%' AND LENGTH(lookup) <= $maxLookahead AND LENGTH(lookup) >= $minLookAhead ORDER BY length_of_longest_match DESC LIMIT 1");
    final longestMatchResult = stmt.select();
    if (longestMatchResult.isNotEmpty) {
      final longestMatch = longestMatchResult.first['length_of_longest_match'];
      maxLookahead = min(longestMatch, maxLookahead);
      for (int j = maxLookahead; j >= minLookAhead; j--) {
        final lookup = _clipboardText.substring(i, i + j);
        final definition = lookupExactMatch(db, lookup);
        if (definition.isNotEmpty) {
          _translatedText.add(definition);
          return j;
        }
      }
    } else {
      return 0;
    }
    return 0;
  }

  void removeDuplicates() {
    final seen = <String>{};
    _translatedText.removeWhere((element) {
      final key = element['simplified'];
      if (seen.contains(key)) {
        return true;
      } else {
        seen.add(key);
        return false;
      }
    });
  }

  void translateClipboard(String text) {
    Directory current = Directory.current;
    String workingDir = current.path;
    final sqlite3.Database db = sqlite3.sqlite3.open('$workingDir/cedict.db');
    int i = 0;
    _translatedText = [];
    text = text.trim();
    while (i < text.length) {
      if (!isChinese(text[i])) {
        i++;
        continue;
      }
      int lookAheadLength = lookaheadAndTranslate(i, 4, text.length, text, db);
      if (lookAheadLength == 0) {
        lookAheadLength = lookaheadAndTranslate(i, 2, 4, text, db);
      }
      if (lookAheadLength == 0) {
        final definition = lookupExactMatch(db, text[i]);
        if (definition.isNotEmpty) {
          _translatedText.add(definition);
        }
        lookAheadLength = 1;
      }
      i += lookAheadLength;
    }
    removeDuplicates();
  }

  void readClipboard() async {
    // wrap in try catch to prevent app from crashing
    try {
      final data = await FlutterClipboard.paste();
      if (data == _clipboardText) return;
      _clipboardText = data;
      translateClipboard(_clipboardText);
      notifyListeners();
    } catch (e) {
      print(e);
    }
  }

  // run timer
  Timer? _timer;
  void startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      readClipboard();
    });
  }
}

class _MyHomePageState extends State<MyHomePage> {
  var clipboardReader = ClipboardReader();
  // run timer
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
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    final style = Theme.of(context).textTheme.headlineLarge;
    final line_height = style!.fontSize! * TextProperties.fontSizeFactor;
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
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
              // Padding(
              //   padding: const EdgeInsets.all(textProperties.padding),
              //   child: Text(
              //     _clipboardText,
              //     style: Theme.of(context).textTheme.headlineMedium,
              //   ),
              // ),
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
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
