/// Reshapes Arabic text for PDF rendering by converting characters
/// to their correct Unicode Presentation Forms-B (U+FE70–U+FEFF)
/// and performs visual RTL reordering so that the resulting string
/// can be rendered in a left-to-right text context.
///
/// The `pdf` package's built-in bidi algorithm conflicts with PF-B
/// characters, so we bypass it (via textDirection: ltr on pw.Text)
/// and handle both shaping and visual ordering here.
class ArabicPdfReshaper {
  ArabicPdfReshaper._();

  /// Reshape Arabic text and reorder for visual RTL display.
  /// Non-Arabic-only strings pass through unchanged.
  static String reshape(String text) {
    if (text.isEmpty) return text;
    return text.split('\n').map(_reshapeLine).join('\n');
  }

  static String _reshapeLine(String line) {
    if (line.isEmpty) return line;
    final shaped = _shape(line);
    if (!_containsPFB(shaped)) return shaped;
    return _visualReorder(shaped);
  }

  // ────────────────────────────────────────────────────────
  //  VISUAL RTL REORDERING
  // ────────────────────────────────────────────────────────

  /// Whether the string contains any Presentation Forms-B characters.
  static bool _containsPFB(String text) {
    for (final r in text.runes) {
      if (_isPFB(r)) return true;
    }
    return false;
  }

  static bool _isPFB(int c) => c >= 0xFE70 && c <= 0xFEFF;

  /// Reorder a shaped line for visual RTL display in an LTR renderer.
  ///
  /// Algorithm: reverse word order, then reverse characters within
  /// Arabic words (preserving grapheme clusters so diacritics stay
  /// attached to their base characters).
  static String _visualReorder(String text) {
    final words = text.split(' ');
    final result = words.reversed.map((word) {
      if (_wordHasArabic(word)) return _reverseGraphemes(word);
      return word;
    }).toList();
    return result.join(' ');
  }

  static bool _wordHasArabic(String word) {
    for (final r in word.runes) {
      if (_isPFB(r)) return true;
    }
    return false;
  }

  /// Reverse character order within a word, keeping diacritics
  /// attached to their base characters.
  static String _reverseGraphemes(String word) {
    final runes = word.runes.toList();
    final clusters = <List<int>>[];
    for (final r in runes) {
      if (_isDiacritic(r) && clusters.isNotEmpty) {
        clusters.last.add(r);
      } else {
        clusters.add([r]);
      }
    }
    return String.fromCharCodes(
      clusters.reversed.expand((c) => c).toList(),
    );
  }

  // ────────────────────────────────────────────────────────
  //  ARABIC POSITIONAL FORM SHAPING (PF-B)
  // ────────────────────────────────────────────────────────

  static String _shape(String text) {
    final runes = text.runes.toList();
    final out = <int>[];

    for (var i = 0; i < runes.length; i++) {
      final c = runes[i];

      if (_isDiacritic(c)) {
        out.add(c);
        continue;
      }

      if (c == 0x0640) {
        out.add(c);
        continue;
      }

      final forms = _forms[c];
      if (forms == null) {
        out.add(c);
        continue;
      }

      // ── Lam-Alef ligature ──
      if (c == 0x0644) {
        final nextIdx = _nextNonDiacriticIdx(runes, i + 1);
        if (nextIdx != null) {
          final lig = _lamAlef[runes[nextIdx]];
          if (lig != null) {
            final rightConn = _prevConnectsLeft(runes, i);
            out.add(lig[rightConn ? 1 : 0]);
            i = nextIdx;
            continue;
          }
        }
      }

      // ── Regular Arabic letter ──
      final rightConn = _prevConnectsLeft(runes, i);
      final leftConn = forms[2] != 0 && _nextIsArabic(runes, i);

      int fi;
      if (rightConn && leftConn) {
        fi = 3; // medial
      } else if (rightConn) {
        fi = 1; // final
      } else if (leftConn) {
        fi = 2; // initial
      } else {
        fi = 0; // isolated
      }

      out.add(forms[fi] != 0 ? forms[fi] : forms[0]);
    }

    return String.fromCharCodes(out);
  }

  // ── Helpers ──

  static bool _isDiacritic(int c) =>
      (c >= 0x064B && c <= 0x065F) ||
      (c >= 0x0610 && c <= 0x061A) ||
      c == 0x0670 ||
      (c >= 0x06D6 && c <= 0x06ED);

  static bool _prevConnectsLeft(List<int> r, int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (_isDiacritic(r[j])) continue;
      final p = r[j];
      if (p == 0x0640) return true;
      final f = _forms[p];
      return f != null && f[2] != 0;
    }
    return false;
  }

  static bool _nextIsArabic(List<int> r, int i) {
    for (var j = i + 1; j < r.length; j++) {
      if (_isDiacritic(r[j])) continue;
      return _forms.containsKey(r[j]) || r[j] == 0x0640;
    }
    return false;
  }

  static int? _nextNonDiacriticIdx(List<int> r, int start) {
    for (var j = start; j < r.length; j++) {
      if (!_isDiacritic(r[j])) return j;
    }
    return null;
  }

  // ── Lam-Alef ligatures [isolated, final] ──

  static const _lamAlef = <int, List<int>>{
    0x0622: [0xFEF5, 0xFEF6], // لآ
    0x0623: [0xFEF7, 0xFEF8], // لأ
    0x0625: [0xFEF9, 0xFEFA], // لإ
    0x0627: [0xFEFB, 0xFEFC], // لا
  };

  // ── Presentation forms: [isolated, final, initial, medial] ──

  static const _forms = <int, List<int>>{
    0x0621: [0xFE80, 0, 0, 0], // ء
    0x0622: [0xFE81, 0xFE82, 0, 0], // آ
    0x0623: [0xFE83, 0xFE84, 0, 0], // أ
    0x0624: [0xFE85, 0xFE86, 0, 0], // ؤ
    0x0625: [0xFE87, 0xFE88, 0, 0], // إ
    0x0626: [0xFE89, 0xFE8A, 0xFE8B, 0xFE8C], // ئ
    0x0627: [0xFE8D, 0xFE8E, 0, 0], // ا
    0x0628: [0xFE8F, 0xFE90, 0xFE91, 0xFE92], // ب
    0x0629: [0xFE93, 0xFE94, 0, 0], // ة
    0x062A: [0xFE95, 0xFE96, 0xFE97, 0xFE98], // ت
    0x062B: [0xFE99, 0xFE9A, 0xFE9B, 0xFE9C], // ث
    0x062C: [0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0], // ج
    0x062D: [0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4], // ح
    0x062E: [0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8], // خ
    0x062F: [0xFEA9, 0xFEAA, 0, 0], // د
    0x0630: [0xFEAB, 0xFEAC, 0, 0], // ذ
    0x0631: [0xFEAD, 0xFEAE, 0, 0], // ر
    0x0632: [0xFEAF, 0xFEB0, 0, 0], // ز
    0x0633: [0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4], // س
    0x0634: [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8], // ش
    0x0635: [0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC], // ص
    0x0636: [0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0], // ض
    0x0637: [0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4], // ط
    0x0638: [0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8], // ظ
    0x0639: [0xFEC9, 0xFECA, 0xFECB, 0xFECC], // ع
    0x063A: [0xFECD, 0xFECE, 0xFECF, 0xFED0], // غ
    0x0641: [0xFED1, 0xFED2, 0xFED3, 0xFED4], // ف
    0x0642: [0xFED5, 0xFED6, 0xFED7, 0xFED8], // ق
    0x0643: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC], // ك
    0x0644: [0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0], // ل
    0x0645: [0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4], // م
    0x0646: [0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8], // ن
    0x0647: [0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC], // ه
    0x0648: [0xFEED, 0xFEEE, 0, 0], // و
    0x0649: [0xFEEF, 0xFEF0, 0, 0], // ى
    0x064A: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4], // ي
  };
}
