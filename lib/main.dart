import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:persian/persian.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'spell_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بررسی املا فارسی و کردی',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7377),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7377),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const SpellCheckPage(),
      locale: const Locale('fa', 'IR'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );
  }
}

class SpellCheckPage extends StatefulWidget {
  const SpellCheckPage({super.key});

  @override
  State<SpellCheckPage> createState() => _SpellCheckPageState();
}

class _SpellCheckPageState extends State<SpellCheckPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _selectedLanguage = 'fa';
  List<SpellIssue> _issues = [];
  String _statusMessage = '';
  bool _isChecking = false;
  bool _useOnline = true;
  bool _dictLoaded = false;

  Set<String> _dictionary = {};
  Set<String> _customDictionary = {};

  // دیکشنری پایه کردی سورانی
  static const Set<String> _kurdishBase = {
    'سڵاو', 'سپاس', 'سوپاس', 'بەڵێ', 'نەخێر', 'تکایە', 'ببورە',
    'کتێب', 'قوتابخانە', 'زانکۆ', 'ماڵ', 'ئۆتۆمبێل', 'سەیارە',
    'منداڵ', 'ژن', 'پیاو', 'باوک', 'دایک', 'برا', 'خوشک',
    'ئاو', 'نان', 'خواردن', 'چای', 'قاوە', 'میوە',
    'ئەمڕۆ', 'سبەینێ', 'دوێنێ', 'هەفتە', 'مانگ', 'ساڵ',
    'باش', 'خراپ', 'جوان', 'گەورە', 'بچووک', 'خێرا', 'هێواش',
    'چوون', 'هاتن', 'بینین', 'وتن', 'بیستن', 'خوێندن', 'نووسین',
    'هەیە', 'بوو', 'دەبێت', 'دەکات', 'دەچێت', 'دێت',
    'ئیران', 'ته‌ران', 'هه‌ولێر', 'سلێمانی', 'دهۆک', 'کەرکوک',
    'کوردستان', 'کورد', 'زمان', 'زمانی', 'کوردی',
    'خۆشەویستی', 'خێزان', 'دۆست', 'هاوڕێ',
    'کار', 'پیشە', 'پارە', 'بازاڕ', 'فرۆشتن', 'کڕین',
    'رۆژ', 'شەو', 'بەیانی', 'ئێوارە', 'نیوەڕۆ',
  };

  @override
  void initState() {
    super.initState();
    _loadDictionaries();
  }

  Future<void> _loadDictionaries() async {
    try {
      // بارگذاری دیکشنری فارسی از فایل asset
      final persianText = await rootBundle.loadString('assets/persian_common.txt');
      final persianWords = persianText
          .split('\n')
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toSet();

      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getStringList('custom_dict') ?? [];

      setState(() {
        _dictionary = {...persianWords, ..._kurdishBase};
        _customDictionary = custom.toSet();
        _dictLoaded = true;
      });
    } catch (e) {
      // اگر فایل پیدا نشد، از دیکشنری پایه استفاده کن
      setState(() {
        _dictionary = {..._kurdishBase};
        _dictLoaded = true;
      });
    }
  }

  Future<void> _saveCustomDictionary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_dict', _customDictionary.toList());
  }

  List<SpellIssue> checkPersianRules(String text) {
    List<SpellIssue> issues = [];

    // نیم‌فاصله قبل از «ها»
    final haPattern = RegExp(r'([ا-یآء])\s+(ها(?:ی|یی|یم|یت|یش|مان|تان|شان)?)');
    for (final match in haPattern.allMatches(text)) {
      issues.add(SpellIssue(
        start: match.start,
        end: match.end,
        original: match.group(0)!,
        suggestion: '${match.group(1)}\u200c${match.group(2)}',
        message: 'فاصله قبل از «ها» باید نیم‌فاصله باشد',
        type: IssueType.halfSpace,
      ));
    }

    // «می» و «نمی»
    final miPattern = RegExp(r'(^|\s)(ن?می)\s+([ا-یآء])');
    for (final match in miPattern.allMatches(text)) {
      issues.add(SpellIssue(
        start: match.start + (match.group(1)?.length ?? 0),
        end: match.end,
        original: '${match.group(2)} ${match.group(3)}',
        suggestion: '${match.group(2)}\u200c${match.group(3)}',
        message: '«می» و «نمی» باید با نیم‌فاصله به فعل بچسبند',
        type: IssueType.halfSpace,
      ));
    }

    // حروف عربی
    if (text.contains('ي') || text.contains('ك')) {
      issues.add(SpellIssue(
        start: 0,
        end: 0,
        original: '',
        suggestion: normalizePersianKurdish(text),
        message: 'حروف عربی (ي و ك) به معادل فارسی تبدیل شدند',
        type: IssueType.character,
      ));
    }

    // فاصله اضافی
    final extraSpace = RegExp(r' {2,}');
    for (final match in extraSpace.allMatches(text)) {
      issues.add(SpellIssue(
        start: match.start,
        end: match.end,
        original: match.group(0)!,
        suggestion: ' ',
        message: 'فاصله اضافی وجود دارد',
        type: IssueType.spacing,
      ));
    }

    // علائم نگارشی
    final punctPattern = RegExp(r'([.!؟،؛:])([ا-یآءa-zA-Z])');
    for (final match in punctPattern.allMatches(text)) {
      issues.add(SpellIssue(
        start: match.start,
        end: match.end,
        original: match.group(0)!,
        suggestion: '${match.group(1)} ${match.group(2)}',
        message: 'بعد از علائم نگارشی باید فاصله باشد',
        type: IssueType.punctuation,
      ));
    }

    return issues;
  }

  List<SpellIssue> checkSpellingLocal(String text) {
    if (!_dictLoaded) return [];

    final allDict = {..._dictionary, ..._customDictionary};
    final issues = <SpellIssue>[];
    final wordPattern = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]+');

    for (final match in wordPattern.allMatches(text)) {
      final word = match.group(0)!;
      if (word.length < 3) continue;

      // اگر در دیکشنری نیست
      if (!allDict.contains(word)) {
        final suggestions = findSuggestions(word, allDict, maxDistance: 2, maxSuggestions: 4);
        issues.add(SpellIssue(
          start: match.start,
          end: match.end,
          original: word,
          suggestion: suggestions.isNotEmpty ? suggestions.first : '',
          message: suggestions.isNotEmpty
              ? 'املای احتمالی نادرست'
              : 'کلمه در دیکشنری یافت نشد',
          type: IssueType.spelling,
          allSuggestions: suggestions,
        ));
      }
    }
    return issues;
  }

  Future<List<SpellIssue>> checkOnline(String text) async {
    if (!_useOnline || _selectedLanguage != 'fa') return [];

    try {
      final response = await http.post(
        Uri.parse('https://api.languagetool.org/v2/check'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'text': text,
          'language': 'fa',
          'enabledOnly': 'false',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final matches = data['matches'] as List? ?? [];
        return matches.map((m) {
          final replacements = (m['replacements'] as List?)
                  ?.map((r) => r['value'] as String)
                  .toList() ??
              [];
          return SpellIssue(
            start: m['offset'] as int,
            end: (m['offset'] as int) + (m['length'] as int),
            original: text.substring(m['offset'], m['offset'] + m['length']),
            suggestion: replacements.isNotEmpty ? replacements.first : '',
            message: m['message'] as String? ?? 'خطای نگارشی',
            type: IssueType.grammar,
            allSuggestions: replacements,
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> performCheck() async {
    setState(() {
      _isChecking = true;
      _issues = [];
      _statusMessage = '';
    });

    String text = _controller.text;
    if (text.trim().isEmpty) {
      setState(() {
        _statusMessage = 'لطفاً متنی وارد کنید.';
        _isChecking = false;
      });
      return;
    }

    // نرمال‌سازی
    final normalized = normalizePersianKurdish(text);
    final withPersianNums = _selectedLanguage == 'fa' ? normalized.withPersianNumbers() : normalized;

    if (withPersianNums != text) {
      _controller.value = TextEditingValue(
        text: withPersianNums,
        selection: TextSelection.collapsed(offset: withPersianNums.length),
      );
      text = withPersianNums;
    }

    List<SpellIssue> allIssues = [];
    allIssues.addAll(checkPersianRules(text));
    allIssues.addAll(checkSpellingLocal(text));

    if (_useOnline) {
      final online = await checkOnline(text);
      allIssues.addAll(online);
    }

    // حذف تکراری
    final seen = <String>{};
    allIssues = allIssues.where((i) {
      final key = '${i.start}-${i.end}-${i.message}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();

    setState(() {
      _issues = allIssues;
      if (allIssues.isEmpty) {
        _statusMessage = '✓ هیچ خطای املایی یا نگارشی پیدا نشد.';
      } else {
        _statusMessage = '${allIssues.length} مورد پیدا شد:';
      }
      _isChecking = false;
    });
  }

  void applySuggestion(SpellIssue issue) {
    if (issue.suggestion.isEmpty) return;
    final text = _controller.text;
    final newText = text.replaceRange(issue.start, issue.end, issue.suggestion);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: issue.start + issue.suggestion.length),
    );
    setState(() {
      _issues.remove(issue);
      if (_issues.isEmpty) _statusMessage = '✓ همه موارد اصلاح شدند.';
    });
  }

  void addToDictionary(String word) {
    setState(() {
      _customDictionary.add(word);
      _issues.removeWhere((i) => i.original == word);
    });
    _saveCustomDictionary();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('«$word» به دیکشنری شخصی اضافه شد')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بررسی املا و نگارش', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0D7377),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_useOnline ? Icons.cloud_done : Icons.cloud_off),
            tooltip: _useOnline ? 'آنلاین فعال' : 'فقط آفلاین',
            onPressed: () {
              setState(() => _useOnline = !_useOnline);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_useOnline ? 'بررسی آنلاین فعال شد' : 'فقط بررسی آفلاین'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // انتخاب زبان
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text('زبان:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'fa', label: Text('فارسی'), icon: Icon(Icons.language, size: 18)),
                        ButtonSegment(value: 'ckb', label: Text('کوردی'), icon: Icon(Icons.language, size: 18)),
                      ],
                      selected: {_selectedLanguage},
                      onSelectionChanged: (s) => setState(() => _selectedLanguage = s.first),
                    ),
                  ),
                ],
              ),
            ),

            // وضعیت دیکشنری
            if (!_dictLoaded)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),

            // فیلد متن
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      expands: true,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 17, height: 1.85),
                      decoration: InputDecoration(
                        hintText: _selectedLanguage == 'fa'
                            ? 'متن فارسی خود را اینجا بنویسید...'
                            : 'دەقی کوردی خۆت لێرە بنووسە...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                      spellCheckConfiguration: const SpellCheckConfiguration(
                        spellCheckService: DefaultSpellCheckService(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // دکمه
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isChecking || !_dictLoaded ? null : performCheck,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.spellcheck_rounded),
                  label: Text(
                    _isChecking ? 'در حال بررسی...' : 'بررسی املا و نگارش',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D7377),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // نتایج
            if (_statusMessage.isNotEmpty || _issues.isNotEmpty)
              Flexible(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: _issues.isEmpty
                        ? (isDark ? Colors.green.shade900.withOpacity(0.3) : Colors.green.shade50)
                        : (isDark ? Colors.orange.shade900.withOpacity(0.3) : Colors.orange.shade50),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _issues.isEmpty ? Colors.green.shade300 : Colors.orange.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _issues.isEmpty ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                        ),
                      ),
                      if (_issues.isNotEmpty)
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _issues.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final issue = _issues[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                title: Text(issue.message, style: const TextStyle(fontSize: 14)),
                                subtitle: issue.original.isNotEmpty
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '«${issue.original}»${issue.suggestion.isNotEmpty ? ' → «${issue.suggestion}»' : ''}',
                                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                          if (issue.allSuggestions.length > 1)
                                            Wrap(
                                              spacing: 6,
                                              children: issue.allSuggestions
                                                  .skip(1)
                                                  .map((s) => ActionChip(
                                                        label: Text(s, style: const TextStyle(fontSize: 12)),
                                                        onPressed: () {
                                                          final newIssue = SpellIssue(
                                                            start: issue.start,
                                                            end: issue.end,
                                                            original: issue.original,
                                                            suggestion: s,
                                                            message: issue.message,
                                                            type: issue.type,
                                                          );
                                                          applySuggestion(newIssue);
                                                        },
                                                      ))
                                                  .toList(),
                                            ),
                                        ],
                                      )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (issue.suggestion.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.check_circle, color: Colors.green),
                                        tooltip: 'اعمال',
                                        onPressed: () => applySuggestion(issue),
                                      ),
                                    if (issue.original.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.playlist_add, size: 22),
                                        tooltip: 'افزودن به دیکشنری',
                                        onPressed: () => addToDictionary(issue.original),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class SpellIssue {
  final int start;
  final int end;
  final String original;
  final String suggestion;
  final String message;
  final IssueType type;
  final List<String> allSuggestions;

  SpellIssue({
    required this.start,
    required this.end,
    required this.original,
    required this.suggestion,
    required this.message,
    required this.type,
    this.allSuggestions = const [],
  });
}

enum IssueType {
  halfSpace,
  character,
  spacing,
  punctuation,
  grammar,
  spelling,
}
