import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:tuple/tuple.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';

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

  Tuple2<String, int> getVowel(String pinyin) {
    for (int i = 0; i < pinyin.length; i++) {
      final c = pinyin[i];
      if (c == 'a' ||
          c == 'e' ||
          c == 'i' ||
          c == 'o' ||
          c == 'u' ||
          c == 'ü') {
        return Tuple2(c, i);
      }
    }
    return const Tuple2('', -1);
  }

  String addPinyinTones(String pinyin) {
    final toneMap = {
      'a': ['ā', 'á', 'ǎ', 'à'],
      'e': ['ē', 'é', 'ě', 'è'],
      'i': ['ī', 'í', 'ǐ', 'ì'],
      'o': ['ō', 'ó', 'ǒ', 'ò'],
      'u': ['ū', 'ú', 'ǔ', 'ù'],
      'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
    };
    final pinyinWords = pinyin.split(' ');
    for (int i = 0; i < pinyinWords.length; i++) {
      final pinyinWord = pinyinWords[i];
      final vowelAndIndex = getVowel(pinyinWord);
      final vowel = vowelAndIndex.item1;
      final vowelIndex = vowelAndIndex.item2;
      final tone = pinyinWord[pinyinWord.length - 1];
      final toneIndex = int.parse(tone) - 1;
      if (vowelIndex != -1 && toneIndex >= 0 && toneIndex <= 3) {
        final newVowel = toneMap[vowel]![toneIndex];
        pinyinWords[i] =
            pinyinWord.replaceRange(vowelIndex, vowelIndex + 1, newVowel);
        pinyinWords[i] = pinyinWords[i].substring(0, pinyinWords[i].length - 1);
      } else if (toneIndex == 4 || toneIndex == -1) {
        pinyinWords[i] = pinyinWord.substring(0, pinyinWord.length - 1);
      }
    }
    return pinyinWords.join(' ');
  }

  Map<String, dynamic> lookupExactMatch(db, String search) {
    final stmt = db.prepare(
        "SELECT * FROM cedict_lookup INNER JOIN cedict ON cedict_lookup.cedict_id = cedict.id WHERE lookup = '$search' ORDER BY Definitions DESC,cedict_lookup.id ASC");
    final lookupResult = stmt.select();
    if (lookupResult.isNotEmpty) {
      final row = lookupResult.first;
      final simplified = row['Simplified'];
      final traditional = row['Traditional'];
      final initialPinyin = row['Pinyin'];
      final pinyin = addPinyinTones(initialPinyin);
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

  String cleanText(String text) {
    text = text.trim();
    text = text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    return text;
  }

  void translateClipboard(String text) {
    Directory current = Directory.current;
    String workingDir = current.path;
    final sqlite3.Database db = sqlite3.sqlite3.open('$workingDir/cedict.db');
    int i = 0;
    _translatedText = [];
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
      final text = cleanText(data);
      if (text == _clipboardText) return;
      _clipboardText = text;
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
