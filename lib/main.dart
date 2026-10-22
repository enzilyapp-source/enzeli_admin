import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'admin_file_upload.dart';
import 'admin_location.dart';
import 'report_export.dart';
part 'admin_operations.dart';

// Base URL for the existing backend (Nest + Prisma). Override via:
// flutter run -d chrome --dart-define=API_BASE_URL=https://api.example.com
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  // Shared Render backend for all apps (MVP + Admin)
  defaultValue: 'https://inzeli-api-6heq.onrender.com/api',
);

// Rollup list of games available across the platform
const List<String> kGameOptions = [
  'كوت',
  'بلوت',
  'تريكس',
  'هند',
  'سبيتة',
  'UNO',
  'اونو',
  'شطرنج',
  'دامه',
  'كيرم',
  'دومنه',
  'طاوله',
  'بلياردو',
  'جاكارو',
  'بيبيفوت',
  'قدم',
  'سله',
  'طائره',
  'بولنج',
  'بادل',
  'تنس طاولة',
  'تنس ارضي',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthState();
  await auth.load();
  runApp(ChangeNotifierProvider(create: (_) => auth, child: const AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A6A88)),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Admin Enzily',
      theme: theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      home: const RootRouter(),
    );
  }
}

class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthed) {
      return const LoginScreen();
    }
    return const AdminShell();
  }
}

class AuthState extends ChangeNotifier {
  bool loading = true;
  String? token;
  String? email;

  static const _kAuthKey = 'admin_auth_v1';

  bool get isAuthed => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kAuthKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        token = (m['token'] ?? '').toString();
        email = (m['email'] ?? '').toString();
      } catch (_) {}
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAuthKey, jsonEncode({'token': token, 'email': email}));
  }

  Future<void> logout() async {
    token = null;
    email = null;
    await _save();
    notifyListeners();
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    final api = ApiClient(token: null);
    final res = await api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    if (res.error != null) return res.error;

    final data = res.data;
    final t = data['token']?.toString() ?? '';
    if (t.isEmpty) return 'Token missing';

    token = t;
    this.email = email.trim();
    await _save();
    notifyListeners();
    return null;
  }
}

class ApiResponse {
  final dynamic data; // can be Map or List based on backend response
  final String? error;
  final int? statusCode;
  final String? code;
  ApiResponse({required this.data, this.error, this.statusCode, this.code});
}

class ApiClient {
  final String? token;
  final http.Client? client;
  const ApiClient({required this.token, this.client});

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _authHeaders() {
    return {
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  ApiResponse _failure(
    http.Response response,
    String path,
    Map<String, dynamic> body,
  ) {
    if (response.statusCode == 404 &&
        (path.startsWith('/admin/operations') ||
            path.startsWith('/admin/reports'))) {
      return ApiResponse(
        data: const {},
        statusCode: 404,
        code: 'SERVER_UPDATE_REQUIRED',
        error:
            'نسخة الخادم الحالية لا تدعم هذه الصفحة بعد. يلزم نشر تحديث السيرفر لتفعيلها، ثم اضغط إعادة المحاولة.',
      );
    }
    return ApiResponse(
      data: const {},
      statusCode: response.statusCode,
      code: body['code']?.toString(),
      error: response.statusCode == 401 || response.statusCode == 403
          ? 'الجلسة منتهية أو الحساب لا يملك صلاحية الأدمن. سجّل الدخول مجددًا.'
          : body['message']?.toString() ?? 'تعذر تنفيذ الطلب',
    );
  }

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<ApiResponse> get(String path) async {
    try {
      final resp = await (client?.get ?? http.get)(
        _uri(path),
        headers: _headers(),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return _failure(resp, path, m);
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final resp = await (client?.post ?? http.post)(
        _uri(path),
        headers: _headers(),
        body: jsonEncode(body ?? const {}),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return _failure(resp, path, m);
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> patch(String path, {Map<String, dynamic>? body}) async {
    try {
      final resp = await (client?.patch ?? http.patch)(
        _uri(path),
        headers: _headers(),
        body: jsonEncode(body ?? const {}),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return _failure(resp, path, m);
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> delete(String path) async {
    try {
      final resp = await (client?.delete ?? http.delete)(
        _uri(path),
        headers: _headers(),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return _failure(resp, path, m);
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> uploadFile(
    String path, {
    required List<int> bytes,
    required String filename,
    required String fieldName,
    required String mimeType,
  }) async {
    try {
      final req = http.MultipartRequest('POST', _uri(path));
      req.headers.addAll(_authHeaders());
      req.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      );
      final streamed = await req.send();
      final text = await streamed.stream.bytesToString();
      final m = jsonDecode(text) as Map<String, dynamic>;
      if (streamed.statusCode >= 200 &&
          streamed.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return ApiResponse(
        data: const {},
        error: m['message']?.toString() ?? 'Request failed',
      );
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }
}

Color _parseColor(String input, {Color fallback = const Color(0xFF1A6A88)}) {
  final text = input.trim().replaceAll('#', '');
  if (text.length == 6 || text.length == 8) {
    try {
      final withAlpha = text.length == 8 ? text : 'FF$text';
      return Color(int.parse(withAlpha, radix: 16));
    } catch (_) {}
  }
  return fallback;
}

String _colorCode(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255);
  final g = (c.g * 255.0).round().clamp(0, 255);
  final b = (c.b * 255.0).round().clamp(0, 255);
  final rgb = (r << 16) | (g << 8) | b;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Future<void> _pickColorForController(
  BuildContext context,
  TextEditingController ctrl,
) async {
  final current = _parseColor(ctrl.text);
  final color = await showColorPickerDialog(
    context,
    current,
    title: const Text('اختر لوناً'),
    width: 40,
    height: 40,
    spacing: 12,
    wheelDiameter: 180,
    showColorName: true,
    pickersEnabled: const <ColorPickerType, bool>{
      ColorPickerType.wheel: true,
      ColorPickerType.accent: false,
      ColorPickerType.primary: true,
    },
  );
  ctrl.text = _colorCode(color);
}

Widget _colorField({
  required String label,
  required TextEditingController controller,
  required BuildContext context,
}) {
  final color = _parseColor(controller.text);
  return LayoutBuilder(
    builder: (context, constraints) {
      final field = TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: '#1A6A88'),
      );
      final swatch = InkWell(
        onTap: () => _pickColorForController(context, controller),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      );
      if (constraints.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerEnd, child: swatch),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          swatch,
        ],
      );
    },
  );
}

Widget _responsiveFormLine({
  required List<Widget> fields,
  List<Widget> actions = const [],
  List<int>? flexes,
  double breakpoint = 760,
  double gap = 8,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < breakpoint;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              fields[i],
              if (i != fields.length - 1 || actions.isNotEmpty)
                SizedBox(height: gap),
            ],
            for (var i = 0; i < actions.length; i++) ...[
              SizedBox(width: double.infinity, child: actions[i]),
              if (i != actions.length - 1) SizedBox(height: gap),
            ],
          ],
        );
      }

      final resolvedFlexes = flexes ?? List<int>.filled(fields.length, 1);
      final totalFlex = resolvedFlexes.fold<int>(0, (sum, flex) => sum + flex);
      final itemCount = fields.length + actions.length;
      final totalGap = itemCount > 1 ? gap * (itemCount - 1) : 0.0;
      final availableWidth = (constraints.maxWidth - totalGap)
          .clamp(0.0, double.infinity)
          .toDouble();
      final actionWidth = actions.length * 132.0;
      final fieldSpace = (availableWidth - actionWidth)
          .clamp(0.0, availableWidth)
          .toDouble();

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (var i = 0; i < fields.length; i++)
            SizedBox(
              width:
                  (fieldSpace *
                          (i < resolvedFlexes.length ? resolvedFlexes[i] : 1) /
                          (totalFlex == 0 ? 1 : totalFlex))
                      .clamp(180.0, constraints.maxWidth)
                      .toDouble(),
              child: fields[i],
            ),
          for (final action in actions)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
              child: action,
            ),
        ],
      );
    },
  );
}

TextStyle _mutedTextStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return TextStyle(
    color: Color.lerp(scheme.surface, scheme.onSurface, 0.72),
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
}

String _formatCoord(dynamic value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  if (n == null) return '-';
  return n.toStringAsFixed(5);
}

Widget _locationLockStatus(Map<String, dynamic> item) {
  final locked = item['locationLock'] == true;
  if (!locked) {
    return const Text(
      'الموقع: مفتوح',
      style: TextStyle(fontSize: 12, color: Colors.grey),
    );
  }
  final radius = (item['radiusMeters'] as num?)?.toInt() ?? 100;
  return SelectableText(
    'الموقع: مقفل • ${_formatCoord(item['anchorLat'])}, ${_formatCoord(item['anchorLng'])} • $radiusم',
    style: const TextStyle(fontSize: 12, color: Colors.teal),
  );
}

Widget _monthlyLeadersBlock(dynamic value) {
  final leaders = value is List ? value : const [];
  if (leaders.isEmpty) {
    return const Text(
      'متصدر الشهر: لا توجد ألعاب مربوطة بعد',
      style: TextStyle(fontSize: 12, color: Colors.grey),
    );
  }
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: leaders.map<Widget>((raw) {
      final item = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      final gameId = (item['gameId'] ?? '-').toString();
      final leaderRaw = item['leader'];
      final leader = leaderRaw is Map
          ? Map<String, dynamic>.from(leaderRaw)
          : null;
      final name = (leader?['displayName'] ?? item['leaderName'] ?? '')
          .toString();
      final pearls = leader?['pearls'] ?? item['pearls'];
      final wins = leader?['wins'] ?? item['wins'];
      final played = leader?['playedCount'] ?? item['playedCount'];
      final label = name.trim().isEmpty
          ? '$gameId: لا يوجد لعب'
          : '$gameId: $name • ${pearls ?? 0} لؤلؤة • ${wins ?? 0} فوز • ${played ?? 0} لعب';
      return Chip(
        avatar: const Icon(Icons.emoji_events_outlined, size: 18),
        label: Text(label),
      );
    }).toList(),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    final err = await auth.login(
      email: _emailCtrl.text,
      password: _passCtrl.text,
    );
    if (err != null) {
      setState(() => _error = err);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Admin Enzily',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Backend: $apiBaseUrl',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Log in (admin)'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'هذا الحساب مخصص للمشرفين فقط. تأكد أن المستخدم في الباكند لديه صلاحيات الإدارة.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final api = ApiClient(token: auth.token);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 560;

    final tabs = [
      _TabData('Sponsors', Icons.work_outline, SponsorTab(api: api)),
      _TabData('Dewanyah', Icons.groups_3_outlined, DewanyahTab(api: api)),
      _TabData('التقارير', Icons.analytics_outlined, ReportsTab(api: api)),
      _TabData(
        'الألعاب',
        Icons.sports_esports_outlined,
        GameVisibilityTab(api: api),
      ),
      _TabData(
        'الصيانة',
        Icons.construction_outlined,
        MaintenanceTab(api: api),
      ),
      _TabData('Users', Icons.verified_user_outlined, UsersTab(api: api)),
      _TabData(
        'Notifications',
        Icons.notifications_active_outlined,
        NotificationsTab(api: api),
      ),
    ];

    final content = tabs[_tab].child;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          compact ? tabs[_tab].title : 'Admin Enzily — ${tabs[_tab].title}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (auth.email != null && width >= 430)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 150 : 260),
                  child: Text(
                    auth.email!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 900)
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: tabs
                  .map(
                    (t) => NavigationRailDestination(
                      icon: Icon(t.icon),
                      label: Text(t.title),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: content,
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 760,
                child: NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: tabs
                      .map(
                        (t) => NavigationDestination(
                          icon: Icon(t.icon),
                          label: t.title,
                        ),
                      )
                      .toList(),
                ),
              ),
            )
          : null,
    );
  }
}

class _TabData {
  final String title;
  final IconData icon;
  final Widget child;
  _TabData(this.title, this.icon, this.child);
}

class SponsorTab extends StatefulWidget {
  final ApiClient api;
  const SponsorTab({super.key, required this.api});

  @override
  State<SponsorTab> createState() => _SponsorTabState();
}

class _SponsorTabState extends State<SponsorTab> {
  Future<ApiResponse>? _future;
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _gameIdCtrl = TextEditingController();
  final _prizeCtrl = TextEditingController();
  final _themePrimCtrl = TextEditingController();
  final _themeAccCtrl = TextEditingController();
  final _existingSponsorCtrl = TextEditingController();
  final _existingGameCtrl = TextEditingController();
  final _existingPrizeCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '100');
  String? _message;
  bool _lockEnabled = false;
  bool _locating = false;
  PickedAdminFile? _newSponsorImageFile;
  bool _uploadingSponsorImage = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/admin/sponsors');
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _imageUrlCtrl.dispose();
    _gameIdCtrl.dispose();
    _prizeCtrl.dispose();
    _themePrimCtrl.dispose();
    _themeAccCtrl.dispose();
    _existingSponsorCtrl.dispose();
    _existingGameCtrl.dispose();
    _existingPrizeCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.get('/admin/sponsors');
    });
  }

  String? _validateSponsorImage(PickedAdminFile file) {
    const maxBytes = 2 * 1024 * 1024;
    final mime = file.mimeType.toLowerCase();
    final name = file.name.toLowerCase();
    final supported =
        mime == 'image/jpeg' ||
        mime == 'image/png' ||
        mime == 'image/webp' ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
    if (!supported) return 'الصورة لازم تكون JPG أو PNG أو WebP';
    if (file.bytes.length > maxBytes) return 'حجم الصورة لازم يكون 2MB أو أقل';
    return null;
  }

  Future<PickedAdminFile?> _pickSponsorImage() async {
    final file = await pickSponsorImageFile();
    if (!mounted || file == null) return null;
    final validation = _validateSponsorImage(file);
    if (validation != null) {
      setState(() => _message = validation);
      return null;
    }
    return file;
  }

  Future<ApiResponse> _uploadSponsorImage(String code, PickedAdminFile file) {
    return widget.api.uploadFile(
      '/admin/sponsors/${Uri.encodeComponent(code)}/image',
      bytes: file.bytes,
      filename: file.name,
      fieldName: 'image',
      mimeType: file.mimeType,
    );
  }

  Future<void> _pickNewSponsorImage() async {
    final file = await _pickSponsorImage();
    if (!mounted || file == null) return;
    setState(() {
      _newSponsorImageFile = file;
      _message = 'تم اختيار الصورة: ${file.name}';
    });
  }

  Future<void> _createSponsor() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final imageUrl = _imageUrlCtrl.text.trim();
    final themePrimary = _themePrimCtrl.text.trim();
    final themeAccent = _themeAccCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final radius = int.tryParse(_radiusCtrl.text.trim());
    if (code.isEmpty || name.isEmpty) {
      setState(() => _message = 'أدخل الكود والاسم');
      return;
    }
    if (_lockEnabled && (lat == null || lng == null)) {
      setState(
        () => _message = 'فعّل الموقع بعد ما تعبّي Latitude و Longitude',
      );
      return;
    }
    setState(() => _uploadingSponsorImage = true);
    final res = await widget.api.post(
      '/admin/sponsors',
      body: {
        'code': code,
        'name': name,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (themePrimary.isNotEmpty) 'themePrimary': themePrimary,
        if (themeAccent.isNotEmpty) 'themeAccent': themeAccent,
        'locationLock': _lockEnabled,
        if (_lockEnabled && lat != null) 'lockLat': lat,
        if (_lockEnabled && lng != null) 'lockLng': lng,
        if (_lockEnabled && radius != null) 'lockRadius': radius,
      },
    );
    var message = res.error ?? 'تم إنشاء/تحديث الراعي';
    if (res.error == null && _newSponsorImageFile != null) {
      final uploadRes = await _uploadSponsorImage(code, _newSponsorImageFile!);
      message = uploadRes.error ?? 'تم إنشاء الراعي ورفع الصورة';
      if (uploadRes.error == null) {
        _newSponsorImageFile = null;
        _imageUrlCtrl.clear();
      }
    }
    if (!mounted) return;
    setState(() {
      _uploadingSponsorImage = false;
      _message = message;
    });
    _refresh();
  }

  Future<void> _fillSponsorCurrentLocation() async {
    setState(() => _locating = true);
    final location = await readBrowserLocation();
    if (!mounted) return;
    if (location == null) {
      setState(() {
        _locating = false;
        _message = 'المتصفح ما عطانا الموقع. فعّل إذن الموقع وحاول مرة ثانية.';
      });
      return;
    }
    setState(() {
      _locating = false;
      _lockEnabled = true;
      _latCtrl.text = location.latitude.toStringAsFixed(7);
      _lngCtrl.text = location.longitude.toStringAsFixed(7);
      _message = location.accuracy == null
          ? 'تم أخذ موقع الأدمن'
          : 'تم أخذ موقع الأدمن بدقة تقريبية ${location.accuracy!.round()}م';
    });
  }

  Future<void> _addSponsorGame() async {
    final code = _codeCtrl.text.trim();
    final gameId = _gameIdCtrl.text.trim();
    final prize = int.tryParse(_prizeCtrl.text.trim());
    if (code.isEmpty || gameId.isEmpty) {
      setState(() => _message = 'أدخل كود الراعي واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/sponsors/$code/games',
      body: {'gameId': gameId, if (prize != null) 'prizeAmount': prize},
    );
    setState(
      () => _message = res.error ?? 'تم طلب إضافة اللعبة (تأكد من دعم الباكند)',
    );
    _refresh();
  }

  Future<void> _addGameToExisting() async {
    final code = _existingSponsorCtrl.text.trim();
    final gameId = _existingGameCtrl.text.trim();
    final prize = int.tryParse(_existingPrizeCtrl.text.trim());
    if (code.isEmpty || gameId.isEmpty) {
      setState(() => _message = 'أدخل كود الراعي واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/sponsors/$code/games',
      body: {'gameId': gameId, if (prize != null) 'prizeAmount': prize},
    );
    setState(() => _message = res.error ?? 'تم طلب إضافة اللعبة للراعي');
    _refresh();
  }

  Future<void> _editSponsor(Map<String, dynamic> s) async {
    final code = (s['code'] ?? '').toString();
    final nameCtrl = TextEditingController(text: s['name']?.toString() ?? '');
    final imgCtrl = TextEditingController(
      text: s['imageUrl']?.toString() ?? '',
    );
    final primCtrl = TextEditingController(
      text: s['themePrimary']?.toString() ?? '',
    );
    final accCtrl = TextEditingController(
      text: s['themeAccent']?.toString() ?? '',
    );
    final latCtrl = TextEditingController(
      text: s['anchorLat'] == null ? '' : _formatCoord(s['anchorLat']),
    );
    final lngCtrl = TextEditingController(
      text: s['anchorLng'] == null ? '' : _formatCoord(s['anchorLng']),
    );
    final radiusCtrl = TextEditingController(
      text: ((s['radiusMeters'] as num?)?.toInt() ?? 100).toString(),
    );
    var lockEnabled = s['locationLock'] == true;
    var locating = false;
    var uploadingImage = false;
    PickedAdminFile? pickedImage;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('تعديل الراعي $code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم الراعي'),
                ),
                TextField(
                  controller: imgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رابط الصورة أو ارفعي من الجهاز',
                    hintText: 'https://... اختياري',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploadingImage
                            ? null
                            : () async {
                                final file = await _pickSponsorImage();
                                if (!context.mounted || file == null) return;
                                setDialogState(() => pickedImage = file);
                              },
                        icon: const Icon(Icons.upload_file),
                        label: const Text('اختيار صورة من الجهاز'),
                      ),
                      Text(
                        pickedImage?.name ??
                            'الأفضل 1200×1200، JPG/PNG/WebP، أقل من 2MB',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون أساسي',
                  controller: primCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون ثانوي',
                  controller: accCtrl,
                  context: context,
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('قفل ألعاب الراعي بالموقع'),
                  subtitle: const Text(
                    'اختياري. يستخدم موقع الأدمن كنقطة اللعب.',
                  ),
                  value: lockEnabled,
                  onChanged: (v) => setDialogState(() => lockEnabled = v),
                ),
                if (lockEnabled) ...[
                  _responsiveFormLine(
                    fields: [
                      TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: radiusCtrl,
                        decoration: const InputDecoration(
                          labelText: 'النطاق بالمتر',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    actions: [
                      OutlinedButton.icon(
                        onPressed: locating
                            ? null
                            : () async {
                                setDialogState(() => locating = true);
                                final location = await readBrowserLocation();
                                if (!context.mounted) return;
                                setDialogState(() => locating = false);
                                if (location == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'المتصفح ما عطانا الموقع. فعّل إذن الموقع.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                latCtrl.text = location.latitude
                                    .toStringAsFixed(7);
                                lngCtrl.text = location.longitude
                                    .toStringAsFixed(7);
                              },
                        icon: locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('موقعي'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: uploadingImage
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      final lat = double.tryParse(latCtrl.text.trim());
                      final lng = double.tryParse(lngCtrl.text.trim());
                      final radius = int.tryParse(radiusCtrl.text.trim());
                      if (lockEnabled && (lat == null || lng == null)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'أدخل Latitude و Longitude أو استخدم موقعي',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => uploadingImage = true);
                      final patchRes = await widget.api.patch(
                        '/admin/sponsors/$code',
                        body: {
                          'name': nameCtrl.text.trim(),
                          'imageUrl': imgCtrl.text.trim(),
                          'themePrimary': primCtrl.text.trim(),
                          'themeAccent': accCtrl.text.trim(),
                          'locationLock': lockEnabled,
                          if (lockEnabled && lat != null) 'lockLat': lat,
                          if (lockEnabled && lng != null) 'lockLng': lng,
                          if (lockEnabled && radius != null)
                            'lockRadius': radius,
                        },
                      );
                      var error = patchRes.error;
                      if (error == null && pickedImage != null) {
                        final uploadRes = await _uploadSponsorImage(
                          code,
                          pickedImage!,
                        );
                        error = uploadRes.error;
                      }
                      if (!context.mounted) return;
                      setDialogState(() => uploadingImage = false);
                      if (error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل الحفظ: $error')),
                        );
                        return;
                      }
                      if (mounted) navigator.pop();
                      setState(() => _message = 'تم حفظ الراعي');
                      _refresh();
                    },
              child: uploadingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSponsor(String code) async {
    await widget.api.delete('/admin/sponsors/$code');
    _refresh();
  }

  Future<void> _snapshotSponsor(String code) async {
    final res = await widget.api.post(
      '/admin/sponsors/$code/monthly-leaders/snapshot',
    );
    setState(() => _message = res.error ?? 'تم حفظ نتيجة الشهر للراعي');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            const Text(
              'الرعاة',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const Spacer(),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<ApiResponse>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final res = snap.data;
            if (res == null || res.error != null) {
              return SizedBox(
                height: 120,
                child: Center(child: Text(res?.error ?? 'فشل تحميل الرعاة')),
              );
            }
            final data = res.data;
            final list = data is List ? data : const [];
            if (list.isEmpty) {
              return const SizedBox(
                height: 120,
                child: Center(child: Text('لا يوجد رعاة بعد')),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final s = list[i] as Map<String, dynamic>;
                      final code = (s['code'] ?? '').toString();
                      final name = (s['name'] ?? code).toString();
                      final games =
                          (s['SponsorGame'] as List?) ??
                          (s['games'] as List?) ??
                          const [];
                      final imageUrl = (s['imageUrl'] ?? '').toString();
                      final themePrim = (s['themePrimary'] ?? '').toString();
                      final themeAcc = (s['themeAccent'] ?? '').toString();
                      final monthlyLeaders = s['monthlyLeaders'];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$name — $code',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 6),
                              if (imageUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    height: 92,
                                    width: double.infinity,
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: Colors.grey.shade200,
                                                alignment: Alignment.center,
                                                child: const Text(
                                                  'تعذر تحميل صورة الراعي',
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                              if (themePrim.isNotEmpty || themeAcc.isNotEmpty)
                                Text(
                                  'الألوان: $themePrim / $themeAcc',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              const SizedBox(height: 4),
                              _locationLockStatus(s),
                              const SizedBox(height: 8),
                              if (games.isEmpty)
                                const Text('لا توجد ألعاب مربوطة')
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: games.map<Widget>((g) {
                                    final mg = g as Map<String, dynamic>;
                                    final gid = (mg['gameId'] ?? '').toString();
                                    final prize = (mg['prizeAmount'] as num?)
                                        ?.toInt();
                                    return Chip(
                                      label: Text(
                                        prize != null
                                            ? '$gid • جائزة $prize'
                                            : gid,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 8),
                              _monthlyLeadersBlock(monthlyLeaders),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () => _editSponsor(s),
                                    child: const Text('تعديل'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _snapshotSponsor(code),
                                    icon: const Icon(
                                      Icons.emoji_events_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('حفظ نتيجة الشهر'),
                                  ),
                                  TextButton(
                                    onPressed: () => _deleteSponsor(code),
                                    child: const Text(
                                      'حذف',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (i != list.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إنشاء راعي / لعبة',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'كود الراعي',
                      ),
                    ),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم الراعي',
                      ),
                    ),
                    TextField(
                      controller: _imageUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'رابط صورة المربع أو ارفعي من الجهاز',
                        hintText: 'https://... اختياري',
                      ),
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _uploadingSponsorImage ? null : _createSponsor,
                      child: const Text('إنشاء راعي'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _uploadingSponsorImage
                          ? null
                          : _pickNewSponsorImage,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('اختيار صورة من الجهاز'),
                    ),
                    Text(
                      _newSponsorImageFile?.name ??
                          'المقاس الأفضل 1200×1200، JPG/PNG/WebP، أقل من 2MB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون أساسي (Hex)',
                  controller: _themePrimCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون ثانوي (Hex)',
                  controller: _themeAccCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('قفل ألعاب الراعي بمنطقة محددة'),
                  subtitle: const Text(
                    'اختياري. إذا تفعل، اللاعب لازم يكون داخل النطاق.',
                  ),
                  value: _lockEnabled,
                  onChanged: (v) => setState(() => _lockEnabled = v),
                ),
                if (_lockEnabled) ...[
                  _responsiveFormLine(
                    fields: [
                      TextField(
                        controller: _latCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: _lngCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: _radiusCtrl,
                        decoration: const InputDecoration(
                          labelText: 'النطاق بالمتر',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _locating
                            ? null
                            : _fillSponsorCurrentLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('استخدام موقعي'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    DropdownButtonFormField<String>(
                      initialValue: _gameIdCtrl.text.isEmpty
                          ? null
                          : _gameIdCtrl.text,
                      decoration: const InputDecoration(labelText: 'Game ID'),
                      items: kGameOptions
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _gameIdCtrl.text = v ?? ''),
                    ),
                    TextField(
                      controller: _prizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'جائزة (اختياري)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _addSponsorGame,
                      child: const Text('ربط لعبة'),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: const TextStyle(color: Colors.blue)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إضافة لعبة لراعي موجود',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    TextField(
                      controller: _existingSponsorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'كود الراعي',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _existingGameCtrl.text.isEmpty
                          ? null
                          : _existingGameCtrl.text,
                      decoration: const InputDecoration(labelText: 'Game ID'),
                      items: kGameOptions
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _existingGameCtrl.text = v ?? ''),
                    ),
                    TextField(
                      controller: _existingPrizeCtrl,
                      decoration: const InputDecoration(labelText: 'جائزة'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _addGameToExisting,
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DewanyahTab extends StatefulWidget {
  final ApiClient api;
  const DewanyahTab({super.key, required this.api});

  @override
  State<DewanyahTab> createState() => _DewanyahTabState();
}

class _DewanyahTabState extends State<DewanyahTab> {
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerUserIdCtrl = TextEditingController();
  final _gameCtrl = TextEditingController();
  final _existingDewIdCtrl = TextEditingController();
  final _existingGameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '100');
  final _themePrimCtrl = TextEditingController();
  final _themeAccCtrl = TextEditingController();
  String? _msg;
  bool _lockEnabled = false;
  bool _requireApproval = true;
  bool _locating = false;
  Future<ApiResponse>? _requestsFuture;
  Future<ApiResponse>? _listFuture;

  @override
  void initState() {
    super.initState();
    _refreshRequests();
    _refreshList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerUserIdCtrl.dispose();
    _gameCtrl.dispose();
    _existingDewIdCtrl.dispose();
    _existingGameCtrl.dispose();
    _noteCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _themePrimCtrl.dispose();
    _themeAccCtrl.dispose();
    super.dispose();
  }

  Future<void> _addGameToExistingDewanyah() async {
    final dewId = _existingDewIdCtrl.text.trim();
    final gameId = _existingGameCtrl.text.trim();
    if (dewId.isEmpty || gameId.isEmpty) {
      setState(() => _msg = 'أدخل معرف الديوانية واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/dewanyah/$dewId/games',
      body: {'gameId': gameId},
    );
    setState(() => _msg = res.error ?? 'تم طلب إضافة اللعبة للديوانية');
  }

  void _refreshRequests() {
    setState(() {
      _requestsFuture = widget.api.get('/admin/dewanyah/requests');
    });
  }

  void _refreshList() {
    setState(() {
      _listFuture = widget.api.get('/admin/dewanyah');
    });
  }

  Future<void> _deleteRequest(String id) async {
    final res = await widget.api.delete('/admin/dewanyah/requests/$id');
    setState(() => _msg = res.error ?? 'تم حذف الطلب');
    _refreshRequests();
  }

  Future<void> _createDewanyah() async {
    final name = _nameCtrl.text.trim();
    final owner = _ownerCtrl.text.trim();
    final ownerEmail = _ownerEmailCtrl.text.trim();
    final ownerUserId = _ownerUserIdCtrl.text.trim();
    final game = _gameCtrl.text.trim();
    final themePrimary = _themePrimCtrl.text.trim();
    final themeAccent = _themeAccCtrl.text.trim();
    if (name.isEmpty || game.isEmpty) {
      setState(() => _msg = 'أدخل الاسم واللعبة');
      return;
    }

    double? lat = double.tryParse(_latCtrl.text.trim());
    double? lng = double.tryParse(_lngCtrl.text.trim());
    int? radius = int.tryParse(_radiusCtrl.text.trim());
    if (!_lockEnabled) {
      lat = null;
      lng = null;
      radius = null;
    }
    if (_lockEnabled && (lat == null || lng == null)) {
      setState(() => _msg = 'فعّل الموقع بعد ما تعبّي Latitude و Longitude');
      return;
    }

    final res = await widget.api.post(
      '/admin/dewanyah',
      body: {
        'name': name,
        if (owner.isNotEmpty) 'owner': owner,
        if (ownerEmail.isNotEmpty) 'ownerEmail': ownerEmail,
        if (ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
        'gameId': game,
        'note': _noteCtrl.text.trim(),
        'requireApproval': _requireApproval,
        'locationLock': _lockEnabled,
        if (lat != null && lng != null) 'lockLat': lat,
        if (lat != null && lng != null) 'lockLng': lng,
        if (radius != null) 'lockRadius': radius,
        if (themePrimary.isNotEmpty) 'themePrimary': themePrimary,
        if (themeAccent.isNotEmpty) 'themeAccent': themeAccent,
      },
    );
    setState(() => _msg = res.error ?? 'تم إنشاء الديوانية');
    _refreshRequests();
    _refreshList();
  }

  Future<void> _fillDewanyahCurrentLocation() async {
    setState(() => _locating = true);
    final location = await readBrowserLocation();
    if (!mounted) return;
    if (location == null) {
      setState(() {
        _locating = false;
        _msg = 'المتصفح ما عطانا الموقع. فعّل إذن الموقع وحاول مرة ثانية.';
      });
      return;
    }
    setState(() {
      _locating = false;
      _lockEnabled = true;
      _latCtrl.text = location.latitude.toStringAsFixed(7);
      _lngCtrl.text = location.longitude.toStringAsFixed(7);
      _msg = location.accuracy == null
          ? 'تم أخذ موقع الأدمن'
          : 'تم أخذ موقع الأدمن بدقة تقريبية ${location.accuracy!.round()}م';
    });
  }

  Future<void> _editDewanyah(Map<String, dynamic> d) async {
    final id = (d['id'] ?? '').toString();
    final nameCtrl = TextEditingController(text: d['name']?.toString() ?? '');
    final ownerCtrl = TextEditingController(
      text: d['ownerName']?.toString() ?? '',
    );
    final emailCtrl = TextEditingController(
      text: d['ownerEmail']?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(text: d['note']?.toString() ?? '');
    final imgCtrl = TextEditingController(
      text: d['imageUrl']?.toString() ?? '',
    );
    final primCtrl = TextEditingController(
      text: d['themePrimary']?.toString() ?? '',
    );
    final accCtrl = TextEditingController(
      text: d['themeAccent']?.toString() ?? '',
    );
    final latCtrl = TextEditingController(
      text: d['anchorLat'] == null ? '' : _formatCoord(d['anchorLat']),
    );
    final lngCtrl = TextEditingController(
      text: d['anchorLng'] == null ? '' : _formatCoord(d['anchorLng']),
    );
    final radiusCtrl = TextEditingController(
      text: ((d['radiusMeters'] as num?)?.toInt() ?? 100).toString(),
    );
    var lockEnabled = d['locationLock'] == true;
    var locating = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الديوانية'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                TextField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المالك'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'إيميل المالك'),
                ),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                TextField(
                  controller: imgCtrl,
                  decoration: const InputDecoration(labelText: 'رابط الصورة'),
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون أساسي',
                  controller: primCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون ثانوي',
                  controller: accCtrl,
                  context: context,
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('قفل الديوانية بالموقع'),
                  subtitle: const Text(
                    'اختياري. يستخدم موقع الأدمن كنقطة اللعب.',
                  ),
                  value: lockEnabled,
                  onChanged: (v) => setDialogState(() => lockEnabled = v),
                ),
                if (lockEnabled)
                  _responsiveFormLine(
                    fields: [
                      TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      TextField(
                        controller: radiusCtrl,
                        decoration: const InputDecoration(
                          labelText: 'النطاق بالمتر',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    actions: [
                      OutlinedButton.icon(
                        onPressed: locating
                            ? null
                            : () async {
                                setDialogState(() => locating = true);
                                final location = await readBrowserLocation();
                                if (!context.mounted) return;
                                setDialogState(() => locating = false);
                                if (location == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'المتصفح ما عطانا الموقع. فعّل إذن الموقع.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                latCtrl.text = location.latitude
                                    .toStringAsFixed(7);
                                lngCtrl.text = location.longitude
                                    .toStringAsFixed(7);
                              },
                        icon: locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('موقعي'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final lat = double.tryParse(latCtrl.text.trim());
                final lng = double.tryParse(lngCtrl.text.trim());
                final radius = int.tryParse(radiusCtrl.text.trim());
                if (lockEnabled && (lat == null || lng == null)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'أدخل Latitude و Longitude أو استخدم موقعي',
                      ),
                    ),
                  );
                  return;
                }
                await widget.api.patch(
                  '/admin/dewanyah/$id',
                  body: {
                    'name': nameCtrl.text.trim(),
                    'ownerName': ownerCtrl.text.trim(),
                    'ownerEmail': emailCtrl.text.trim(),
                    'note': noteCtrl.text.trim(),
                    'imageUrl': imgCtrl.text.trim(),
                    'themePrimary': primCtrl.text.trim(),
                    'themeAccent': accCtrl.text.trim(),
                    'locationLock': lockEnabled,
                    if (lockEnabled && lat != null) 'lockLat': lat,
                    if (lockEnabled && lng != null) 'lockLng': lng,
                    if (lockEnabled && radius != null) 'lockRadius': radius,
                  },
                );
                if (mounted) navigator.pop();
                _refreshList();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDewanyah(String id) async {
    await widget.api.delete('/admin/dewanyah/$id');
    _refreshList();
  }

  Future<void> _snapshotDewanyah(String id) async {
    final res = await widget.api.post(
      '/admin/dewanyah/$id/monthly-leaders/snapshot',
    );
    setState(() => _msg = res.error ?? 'تم حفظ نتيجة الشهر للديوانية');
    _refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الديوانيات',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إنشاء ديوانية جديدة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الديوانية',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المالك/المسؤول',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'إيميل المالك (حساب التطبيق)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerUserIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Owner User ID (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _gameCtrl.text.isEmpty
                        ? null
                        : _gameCtrl.text,
                    decoration: const InputDecoration(labelText: 'Game ID'),
                    items: kGameOptions
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _gameCtrl.text = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _colorField(
                    label: 'لون أساسي (Hex)',
                    controller: _themePrimCtrl,
                    context: context,
                  ),
                  const SizedBox(height: 8),
                  _colorField(
                    label: 'لون ثانوي (Hex)',
                    controller: _themeAccCtrl,
                    context: context,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('قفل بالموقع (100م افتراضي)'),
                    value: _lockEnabled,
                    onChanged: (v) => setState(() => _lockEnabled = v),
                    subtitle: const Text('لن يُسمح بالانضمام خارج النطاق'),
                  ),
                  if (_lockEnabled) ...[
                    const SizedBox(height: 6),
                    _responsiveFormLine(
                      fields: [
                        TextField(
                          controller: _latCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                        TextField(
                          controller: _lngCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                        TextField(
                          controller: _radiusCtrl,
                          decoration: const InputDecoration(
                            labelText: 'النطاق بالمتر',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                      actions: [
                        OutlinedButton.icon(
                          onPressed: _locating
                              ? null
                              : _fillDewanyahCurrentLocation,
                          icon: _locating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          label: const Text('استخدام موقعي'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تتطلب موافقة المالك'),
                    value: _requireApproval,
                    onChanged: (v) => setState(() => _requireApproval = v),
                    subtitle: const Text(
                      'الانضمام بالديوانية يحتاج موافقة صاحبها',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _createDewanyah,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('إنشاء'),
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 6),
                    Text(_msg!, style: const TextStyle(color: Colors.blue)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'الديوانيات الحالية',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _refreshList,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<ApiResponse>(
                    future: _listFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final res = snap.data;
                      if (res == null || res.error != null) {
                        return Text(
                          res?.error ?? 'فشل تحميل الديوانيات',
                          style: const TextStyle(color: Colors.grey),
                        );
                      }
                      final list = res.data is List
                          ? (res.data as List)
                          : const [];
                      if (list.isEmpty) {
                        return const Text('لا توجد ديوانيات حالياً');
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 12),
                        itemBuilder: (context, i) {
                          final d = list[i] as Map<String, dynamic>;
                          final id = (d['id'] ?? '').toString();
                          final name = (d['name'] ?? 'ديوانية').toString();
                          final owner = (d['ownerName'] ?? '').toString();
                          final game =
                              ((d['games'] as List?)?.isNotEmpty ?? false)
                              ? (d['games'][0]['gameId']?.toString() ?? '')
                              : (d['gameId'] ?? '').toString();
                          final members = (d['_count']?['members'] ?? 0)
                              .toString();
                          final monthlyLeaders = d['monthlyLeaders'];
                          return ListTile(
                            title: Text(
                              '$name — $game',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  'ID: $id',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (owner.isNotEmpty) Text('المالك: $owner'),
                                Text('الأعضاء: $members'),
                                const SizedBox(height: 4),
                                _locationLockStatus(d),
                                const SizedBox(height: 6),
                                _monthlyLeadersBlock(monthlyLeaders),
                              ],
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                IconButton(
                                  tooltip: 'استخدام المعرّف',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    setState(
                                      () => _existingDewIdCtrl.text = id,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تم نسخ/تعبئة معرف الديوانية',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                TextButton(
                                  onPressed: () => _editDewanyah(d),
                                  child: const Text('تعديل'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _snapshotDewanyah(id),
                                  icon: const Icon(
                                    Icons.emoji_events_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('حفظ النتيجة'),
                                ),
                                TextButton(
                                  onPressed: () => _deleteDewanyah(id),
                                  child: const Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة لعبة لديوانية موجودة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _existingDewIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'معرف الديوانية',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _existingGameCtrl.text.isEmpty
                              ? null
                              : _existingGameCtrl.text,
                          decoration: const InputDecoration(
                            labelText: 'Game ID',
                          ),
                          items: kGameOptions
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _existingGameCtrl.text = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addGameToExistingDewanyah,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'طلبات إنشاء ديوانية',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _refreshRequests,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<ApiResponse>(
                    future: _requestsFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final res = snap.data;
                      if (res == null || res.error != null) {
                        return Text(
                          res?.error ?? 'الطلبات غير متاحة (endpoint مفقود)',
                          style: const TextStyle(color: Colors.grey),
                        );
                      }
                      final data = res.data;
                      final list = data is List ? data : const [];
                      if (list.isEmpty) {
                        return const Text('لا توجد طلبات حاليًا');
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 12),
                        itemBuilder: (context, i) {
                          final r = list[i] as Map<String, dynamic>;
                          final name = (r['name'] ?? 'ديوانية').toString();
                          final owner = (r['owner'] ?? '').toString();
                          final email = (r['ownerEmail'] ?? '').toString();
                          final requestId = (r['id'] ?? '').toString();
                          final ownerUserId =
                              (r['ownerUserId'] ?? r['userId'] ?? '')
                                  .toString();
                          final gameId = (r['gameId'] ?? '').toString();
                          final note = (r['note'] ?? '').toString();
                          return ListTile(
                            title: Text(
                              '$name — $gameId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (owner.isNotEmpty) Text('المالك: $owner'),
                                if (email.isNotEmpty) Text('إيميل: $email'),
                                if (ownerUserId.isNotEmpty)
                                  SelectableText(
                                    'Owner ID: $ownerUserId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (note.isNotEmpty) Text('ملاحظة: $note'),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ownerUserId.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _ownerUserIdCtrl.text = ownerUserId;
                                        if (email.isNotEmpty) {
                                          _ownerEmailCtrl.text = email;
                                        }
                                        if (owner.isNotEmpty) {
                                          _ownerCtrl.text = owner;
                                        }
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'تم تعبئة Owner ID في نموذج الإنشاء',
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('استخدام ID'),
                                  ),
                                if (requestId.isNotEmpty)
                                  IconButton(
                                    tooltip: 'حذف الطلب',
                                    onPressed: () => _deleteRequest(requestId),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UsersTab extends StatefulWidget {
  final ApiClient api;
  const UsersTab({super.key, required this.api});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final _searchCtrl = TextEditingController();
  String? _msg;
  Future<ApiResponse>? _listFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    final q = _searchCtrl.text.trim();
    final suffix = q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}';
    setState(() {
      _listFuture = widget.api.get('/admin/users?limit=200$suffix');
    });
  }

  Future<void> _setLeaderboardHidden({
    required String userId,
    required bool hidden,
  }) async {
    final res = await widget.api.patch(
      '/admin/users/$userId/${hidden ? 'ban' : 'unban'}',
    );
    setState(
      () => _msg =
          res.error ??
          (hidden
              ? 'تم إخفاء المستخدم من الليدربورد'
              : 'تم إظهار المستخدم في الليدربورد'),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المستخدمون',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'بحث (إيميل/اسم/User ID/Public ID/رقم)',
                          ),
                          onSubmitted: (_) => _refresh(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.search),
                        label: const Text('بحث'),
                      ),
                    ],
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 8),
                    Text(_msg!, style: const TextStyle(color: Colors.blue)),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<ApiResponse>(
                      future: _listFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final res = snap.data;
                        if (res == null || res.error != null) {
                          return Center(
                            child: Text(
                              res?.error ?? 'فشل تحميل المستخدمين',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        final list = res.data is List
                            ? (res.data as List)
                            : const [];
                        if (list.isEmpty) {
                          return const Center(child: Text('لا يوجد مستخدمون'));
                        }

                        return ListView.separated(
                          itemCount: list.length,
                          padding: const EdgeInsets.only(bottom: 12),
                          separatorBuilder: (context, _) =>
                              const Divider(height: 12),
                          itemBuilder: (context, i) {
                            final u = list[i] as Map<String, dynamic>;
                            final userId = (u['id'] ?? '').toString();
                            final name = (u['displayName'] ?? '').toString();
                            final email = (u['email'] ?? '').toString();
                            final hidden = u['hideFromLeaderboard'] == true;
                            final isTest = u['isTestAccount'] == true;
                            return ListTile(
                              title: Text(
                                name.isNotEmpty ? name : email,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (email.isNotEmpty) Text(email),
                                  SelectableText(
                                    'ID: $userId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    hidden
                                        ? 'الحالة: مخفي من الليدربورد'
                                        : 'الحالة: ظاهر في الليدربورد',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hidden
                                          ? Colors.orange[800]
                                          : Colors.green[700],
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (isTest)
                                    const Text(
                                      'حساب تجريبي',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  if (!hidden)
                                    TextButton.icon(
                                      onPressed: () => _setLeaderboardHidden(
                                        userId: userId,
                                        hidden: true,
                                      ),
                                      icon: const Icon(
                                        Icons.visibility_off,
                                        size: 18,
                                      ),
                                      label: const Text('إخفاء'),
                                    ),
                                  if (hidden)
                                    TextButton.icon(
                                      onPressed: () => _setLeaderboardHidden(
                                        userId: userId,
                                        hidden: false,
                                      ),
                                      icon: const Icon(
                                        Icons.visibility,
                                        size: 18,
                                      ),
                                      label: const Text('إظهار'),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NotificationsTab extends StatefulWidget {
  final ApiClient api;

  const NotificationsTab({super.key, required this.api});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _awardMonthCtrl = TextEditingController();
  bool _sending = false;
  bool _monthlySending = false;
  bool _seasonNoticeSending = false;
  bool _seasonResetSending = false;
  bool _statusChecking = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _awardMonthCtrl.dispose();
    super.dispose();
  }

  String _pushDeliveryMessage(
    dynamic data, {
    String fallback = 'تم إرسال الإشعار',
  }) {
    if (data is! Map) return fallback;
    if (data['push'] is Map) {
      return _pushDeliveryMessage(data['push'], fallback: fallback);
    }
    final id = (data['id'] ?? '').toString();
    final recipients = data['recipients'] ?? data['directRecipients'];
    final errors = data['errors'];
    final error = data['error'];

    if (id.isNotEmpty) {
      if (recipients != null) {
        return 'تم قبول الإشعار من OneSignal، المستلمين: $recipients';
      }
      return 'تم قبول الإشعار من OneSignal';
    }
    if (errors is List && errors.isNotEmpty) {
      return 'OneSignal رجّع خطأ: ${errors.first}';
    }
    if (error != null && error.toString().isNotEmpty) {
      return 'OneSignal رجّع خطأ: $error';
    }
    return fallback;
  }

  Future<void> _checkOneSignalStatus() async {
    setState(() => _statusChecking = true);
    try {
      final res = await widget.api.get('/admin/notifications/status');
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      final appIdOk = data is Map && data['appIdConfigured'] == true;
      final keyOk = data is Map && data['restApiKeyConfigured'] == true;
      final maskedAppId = data is Map ? data['appId'] : null;
      final audience = data is Map ? data['audience'] : null;
      String message;
      if (!appIdOk || !keyOk) {
        message =
            'ناقص إعدادات OneSignal على الـ API: App ID ${appIdOk ? 'موجود' : 'ناقص'}، REST Key ${keyOk ? 'موجود' : 'ناقص'}';
      } else if (audience is Map && audience['ok'] == true) {
        final subscribed = audience['subscribedSample'] ?? 0;
        final total = audience['totalCount'] ?? 0;
        message =
            'OneSignal مضبوط: $maskedAppId، المشتركين اللي يشوفهم الـ API: $subscribed من أصل $total';
      } else if (audience is Map && audience['error'] != null) {
        message =
            'المفاتيح موجودة، لكن فشل فحص المشتركين: ${audience['error']}';
      } else {
        message = 'OneSignal مضبوط على الـ API: $maskedAppId';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل فحص OneSignal: $e')));
    } finally {
      if (mounted) setState(() => _statusChecking = false);
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب عنوان الإشعار ونصه أولاً')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/broadcast',
        body: {
          'titleAr': title,
          'messageAr': message,
          'title': title,
          'message': message,
        },
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pushDeliveryMessage(res.data))));
      _titleCtrl.clear();
      _messageCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال الإشعار: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMonthlyLeaderboardAwards({bool dryRun = false}) async {
    setState(() => _monthlySending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/monthly-leaderboards',
        body: {
          'limit': 10,
          'dryRun': dryRun,
          if (_awardMonthCtrl.text.trim().isNotEmpty)
            'seasonYm': int.tryParse(_awardMonthCtrl.text.trim()) ?? 0,
        },
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      if (dryRun) {
        final awards = data is Map && data['awards'] is List
            ? data['awards'] as List
            : [];
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('معاينة الفائزين المؤرشفين'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Text(
                  awards.isEmpty
                      ? '${data is Map ? data['notice'] ?? 'لا توجد نتائج' : 'لا توجد نتائج'}'
                      : awards
                            .map(
                              (a) =>
                                  '${a['scope']} • ${a['gameId']} • المركز ${a['rank']}\n${a['leaderName']} — فوز ${a['wins']} | خسارة ${a['losses']}',
                            )
                            .join('\n\n'),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      } else {
        final sent = data is Map ? (data['pushesSent'] ?? 0) : 0;
        final created = data is Map ? (data['eventsCreated'] ?? 0) : 0;
        final errors = data is Map && data['pushErrors'] is List
            ? (data['pushErrors'] as List).length
            : 0;
        final notice = data is Map ? (data['notice'] ?? '') : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تجهيز $created إنجاز وإرسال $sent إشعار؛ تعذر $errors. $notice',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال إشعارات الشهر: $e')));
    } finally {
      if (mounted) setState(() => _monthlySending = false);
    }
  }

  Future<void> _sendSeasonEndedNotice() async {
    setState(() => _seasonNoticeSending = true);
    try {
      final res = await widget.api.post('/admin/notifications/season-ended');
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pushDeliveryMessage(
              res.data,
              fallback: 'تم إرسال إشعار نهاية السيزن',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال إشعار السيزن: $e')));
    } finally {
      if (mounted) setState(() => _seasonNoticeSending = false);
    }
  }

  Future<void> _resetSeasonAndNotify() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تصفير السيزن الشهري؟'),
        content: const Text(
          'بيرجع كل اللاعبين إلى ٥ لآلئ، ويترك التصنيفات محفوظة، ويرسل إشعار نهاية السيزن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _seasonResetSending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/season-reset',
        body: {'sendPush': true},
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      final skipped = data is Map ? data['skipped'] == true : false;
      final users = data is Map ? (data['usersUpdated'] ?? 0) : 0;
      final push = data is Map ? data['push'] : null;
      final pushSent = push is Map ? push['sent'] == true : false;
      final pushResponse = push is Map ? push['response'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped
                ? 'السيزن متصفر مسبقًا لهذا الشهر'
                : pushSent
                ? 'تم تصفير $users مستخدم. ${_pushDeliveryMessage(pushResponse)}'
                : 'تم تصفير $users مستخدم، لكن الإشعار ما انرسل',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تصفير السيزن: $e')));
    } finally {
      if (mounted) setState(() => _seasonResetSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        compact ? 12 : 24,
        compact ? 12 : 24,
        compact ? 132 : 112,
      ),
      children: [
        Text(
          'إشعار عام',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'أرسل إشعارًا لجميع مستخدمي التطبيق.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed:
                (_statusChecking ||
                    _sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _checkOneSignalStatus,
            icon: _statusChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_rounded),
            label: Text(
              _statusChecking ? 'جاري فحص OneSignal...' : 'فحص OneSignal',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _messageCtrl,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'نص الإشعار'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _sending ? 'جاري الإرسال...' : 'إرسال الإشعار للجميع',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'نهاية السيزن الشهري',
          style: TextStyle(
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'يرجع كل اللاعبين إلى ٥ لآلئ، ويبدأ ترتيب الشهر من جديد، وتظل التصنيفات محفوظة.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _sendSeasonEndedNotice,
            icon: _seasonNoticeSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_rounded),
            label: Text(
              _seasonNoticeSending
                  ? 'جاري إرسال إشعار السيزن...'
                  : 'إرسال إشعار نهاية السيزن فقط',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _resetSeasonAndNotify,
            icon: _seasonResetSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt_rounded),
            label: Text(
              _seasonResetSending
                  ? 'جاري تصفير السيزن...'
                  : 'تصفير السيزن وإرسال الإشعار',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'إشعارات الفايزين الشهرية',
          style: TextStyle(
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'العام والسبونسر والدواوين: المركز والفوز والخسارة واللآلئ لكل فائز من النتائج المؤرشفة. الإرسال المتكرر يتجاوز الإشعارات المرسلة سابقًا.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _awardMonthCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'الشهر YYYYMM — فارغ للشهر السابق',
            hintText: '202609',
          ),
        ),
        OutlinedButton.icon(
          onPressed: _monthlySending
              ? null
              : () => _sendMonthlyLeaderboardAwards(dryRun: true),
          icon: const Icon(Icons.preview),
          label: const Text('معاينة بدون إرسال'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_sending || _monthlySending)
                ? null
                : () => _sendMonthlyLeaderboardAwards(),
            icon: _monthlySending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.workspace_premium_rounded),
            label: Text(
              _monthlySending
                  ? 'جاري تجهيز إشعارات الشهر...'
                  : 'إرسال إشعارات الفايزين الشهرية',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
