part of 'main.dart';

Widget _operationsError(String message, VoidCallback retry) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تعذر تحميل الصفحة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(message),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  ),
);

/// Monthly activity and subscription accounting. Keep this separate from sponsor forms.
class ReportsTab extends StatefulWidget {
  final ApiClient api;
  const ReportsTab({super.key, required this.api});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  late DateTime _month;
  bool _includeTests = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _report;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    _month = DateTime(now.year, now.month);
    _load();
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.api.get(
      '/admin/reports/monthly?month=$_monthKey&includeTests=$_includeTests',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.error;
      _report = res.error == null
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    });
  }

  void _move(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  String _achievements(Map user) {
    final badges = (user['achievements'] as List? ?? []).map(
      (a) => '${a['label']} | ${a['gameId']} | ${a['scope']}',
    );
    final placements = (user['leaderboardPlacements'] as List? ?? []).map(
      (a) =>
          'المركز ${a['rank']} | ${a['gameId']} | ${a['sponsorName'] ?? a['dewanyahName'] ?? 'العام'} | فوز ${a['wins']} خسارة ${a['losses']}',
    );
    return [...badges, ...placements].join('؛ ');
  }

  void _showUser(Map user) {
    final purchases = user['subscriptionPurchases'] as List? ?? [];
    final details = [
      'المعرف: ${user['publicId']}',
      if (user['username'] != null) 'اسم المستخدم: @${user['username']}',
      'الفوز: ${user['wins']} | الخسارة: ${user['losses']} | المباريات: ${user['played']}',
      'الإنجازات: ${_achievements(user).isEmpty ? 'لا توجد في هذا الشهر' : _achievements(user)}',
      'شراء وتجديد الاشتراك: ${purchases.length}',
      for (final p in purchases)
        '${p['createdAt']} — رصيد ${p['creditsCharged']} — من ${p['startsAt']} إلى ${p['endsAt']}',
    ].join('\n\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${user['displayName']}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(child: SelectableText(details)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;
    String cell(dynamic value) {
      var text = (value ?? '').toString();
      if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    final summary = report['summary'] as Map;
    final rows = <List<dynamic>>[
      ['الشهر', report['month'], 'المنطقة الزمنية', report['timezone']],
      ['ملاحظة الاشتراكات', report['subscriptionAccountingNote']],
      [
        'الحسابات الكلية الآن',
        summary['totalAccounts'],
        'غير التجريبية الآن',
        summary['registeredUsers'],
      ],
      [
        'اللاعبون بالشهر',
        summary['monthlyPlayers'],
        'المباريات',
        summary['matches'],
      ],
      [
        'شراء وتجديد VIP بالشهر',
        summary['subscriptionPurchases'],
        'رصيد التطبيق المخصوم',
        summary['creditsCharged'],
      ],
      [
        'VIP ساري الآن',
        summary['currentVipUsers'],
        'عمليات لحسابات محذوفة',
        summary['unattributedSubscriptionPurchases'] ?? 0,
      ],
      [],
      [
        'المعرف',
        'الاسم',
        'اسم المستخدم',
        'تاريخ التسجيل',
        'تجريبي',
        'فوز',
        'خسارة',
        'مباريات',
        'آخر لعب',
        'نهاية VIP',
        'عمليات اشتراك الشهر',
        'رصيد اشتراكات الشهر',
        'الإنجازات الشهرية',
      ],
      for (final u in report['users'] as List)
        [
          u['publicId'],
          u['displayName'],
          u['username'],
          u['createdAt'],
          u['isTestAccount'],
          u['wins'],
          u['losses'],
          u['played'],
          u['lastPlayedAt'],
          u['vipUntil'],
          (u['subscriptionPurchases'] as List).length,
          (u['subscriptionPurchases'] as List).fold<int>(
            0,
            (sum, p) => sum + ((p['creditsCharged'] as num?)?.toInt() ?? 0),
          ),
          _achievements(u),
        ],
    ];
    final csv = '\uFEFF${rows.map((r) => r.map(cell).join(',')).join('\r\n')}';
    final downloaded = await exportReportCsv(
      'enzily-${report['month']}.csv',
      csv,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            downloaded ? 'تم تنزيل التقرير' : 'تم نسخ التقرير بصيغة CSV',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _report?['summary'] as Map?;
    final users = _report?['users'] as List? ?? [];
    return ListView(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'تقرير المستخدمين واللاعبين والاشتراكات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: _busy ? null : () => _move(-1),
              tooltip: 'الشهر السابق',
              icon: const Icon(Icons.chevron_left),
            ),
            Text(_monthKey),
            IconButton(
              onPressed: _busy ? null : () => _move(1),
              tooltip: 'الشهر التالي',
              icon: const Icon(Icons.chevron_right),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
            FilledButton.icon(
              onPressed: _report == null || _busy ? null : _export,
              icon: const Icon(Icons.download),
              label: const Text('تصدير CSV'),
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تضمين الحسابات التجريبية في النشاط'),
          value: _includeTests,
          onChanged: _busy
              ? null
              : (v) {
                  setState(() => _includeTests = v == true);
                  _load();
                },
        ),
        const Text(
          'النشاط والإنجازات حسب الشهر بتوقيت الكويت. إجمالي الحسابات وصلاحية VIP يعكسان الوضع الحالي. اللاعب النشط هو من لديه مباراة مسجلة خلال الشهر.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          _operationsError(_error!, () {
            _load();
          }),
        if (summary != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in <String, dynamic>{
                'كل الحسابات الآن': summary['totalAccounts'],
                'حسابات غير تجريبية': summary['registeredUsers'],
                'تجريبية': summary['testAccounts'],
                'تسجيل جديد بالشهر': summary['newUsers'],
                'لاعبون بالشهر': summary['monthlyPlayers'],
                'مباريات الشهر': summary['matches'],
                'إنجازات الشهر': summary['achievements'],
                'VIP ساري الآن': summary['currentVipUsers'],
                'شراء وتجديد VIP بالشهر': summary['subscriptionPurchases'],
                'مشترون مختلفون بالشهر': summary['purchasingUsers'],
                'رصيد مخصوم بالشهر': summary['creditsCharged'],
                'عمليات لحسابات محذوفة':
                    summary['unattributedSubscriptionPurchases'] ?? 0,
              }.entries)
                SizedBox(
                  width: 190,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Text(
                            '${item.value}',
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(item.key, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('${_report!['subscriptionAccountingNote']}'),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('المستخدم')),
                DataColumn(label: Text('فوز')),
                DataColumn(label: Text('خسارة')),
                DataColumn(label: Text('مباريات')),
                DataColumn(label: Text('VIP حتى')),
                DataColumn(label: Text('شراء VIP')),
                DataColumn(label: Text('إنجازات الشهر')),
              ],
              rows: users
                  .map(
                    (u) => DataRow(
                      cells: [
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${u['displayName']}'),
                              Text(
                                u['username'] != null
                                    ? '@${u['username']}'
                                    : '${u['publicId']}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text('${u['wins']}')),
                        DataCell(Text('${u['losses']}')),
                        DataCell(Text('${u['played']}')),
                        DataCell(
                          Text(
                            (u['vipUntil'] ?? 'غير مشترك')
                                .toString()
                                .split('T')
                                .first,
                          ),
                        ),
                        DataCell(
                          Text(
                            '${(u['subscriptionPurchases'] as List).length}',
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 240,
                            child: Text(
                              _achievements(u).isEmpty
                                  ? 'لا توجد — اضغط للتفاصيل'
                                  : _achievements(u),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onTap: () => _showUser(u),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class MaintenanceTab extends StatefulWidget {
  final ApiClient api;
  const MaintenanceTab({super.key, required this.api});
  @override
  State<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<MaintenanceTab> {
  final _message = TextEditingController();
  bool _enabled = false, _busy = true;
  bool _ready = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _ready = false;
    });
    final res = await widget.api.get('/admin/operations');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.error;
      _ready = res.error == null;
      if (res.error == null) {
        _enabled = res.data['maintenanceEnabled'] == true;
        _message.text = '${res.data['maintenanceMessage']}';
      }
    });
  }

  Future<void> _save() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.api.patch(
      '/admin/operations/maintenance',
      body: {'enabled': _enabled, 'message': _message.text.trim()},
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.error;
    });
    if (res.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ وضع الصيانة؛ يصل للتطبيق خلال ٣٠ ثانية'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'صيانة التطبيق',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const Text(
        'تظهر صفحة الصيانة للمستخدمين ويتوقف إنشاء الغرف والانضمام وتسجيل النتائج. تبقى لوحة الأدمن متاحة لإيقاف الصيانة.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        _operationsError(_error!, () {
          _load();
        }),
      SwitchListTile(
        title: const Text('تفعيل صفحة الصيانة'),
        value: _enabled,
        onChanged: _busy || !_ready
            ? null
            : (v) => setState(() => _enabled = v),
      ),
      TextField(
        controller: _message,
        enabled: _ready && !_busy,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'الرسالة الظاهرة للمستخدمين',
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy || !_ready ? null : _save,
        child: const Text('حفظ'),
      ),
    ],
  );
}

class GameVisibilityTab extends StatefulWidget {
  final ApiClient api;
  const GameVisibilityTab({super.key, required this.api});
  @override
  State<GameVisibilityTab> createState() => _GameVisibilityTabState();
}

class _GameVisibilityTabState extends State<GameVisibilityTab> {
  List<dynamic> _games = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.api.get('/admin/operations/games');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.error;
      if (res.error == null) _games = res.data as List;
    });
  }

  Future<void> _toggle(Map game, bool visible) async {
    setState(() => _busy = true);
    final res = await widget.api.patch(
      '/admin/operations/games/${Uri.encodeComponent('${game['id']}')}',
      body: {'visible': visible},
    );
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'الألعاب في القائمة الرئيسية',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const Text(
        'إخفاء اللعبة يحفظ سجل المباريات والإنجازات ويمنع اللعب بها في القسم الرئيسي. ألعاب الدواوين والسبونسر مستقلة. يصل التغيير للتطبيق خلال ٣٠ ثانية.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        _operationsError(_error!, () {
          _load();
        }),
      for (final game in _games)
        SwitchListTile(
          title: Text('${game['name']}'),
          subtitle: Text('${game['category']}'),
          value: game['mainVisible'] == true,
          onChanged: _busy || _error != null
              ? null
              : (v) => _toggle(game as Map, v),
        ),
      OutlinedButton.icon(
        onPressed: _busy ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('تحديث'),
      ),
    ],
  );
}
