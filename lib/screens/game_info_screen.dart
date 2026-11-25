import 'package:flutter/material.dart';
import '../models/script_character.dart';
import '../services/script_library.dart';
import '../widgets/character_avatar.dart';
import '../widgets/character_ability_sheet.dart';
import '../widgets/character_picker_dialog.dart' show teamColor;

class _InfoSection {
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  const _InfoSection(this.icon, this.accent, this.title, this.body);
}

const _ruleSections = <_InfoSection>[
  _InfoSection(Icons.chair_alt, Color(0xFF00E39B), 'تحضير اللعبة', '''
رتّب الكراسي في دائرة حول طاولة مركزية.
افتح كتاب الأسرار وضعه على حامل قريب من راوي القصة.
يُفضَّل للمبتدئين اختيار سيناريو Trouble Brewing.
ضع لوحة ساحة البلدة في المنتصف، مع رمز حياة لكل لاعب، ورموز التصويت، وورقة المسافر.
تُقرأ ورقة القواعد بصوت عالٍ للاعبين الجدد، مع شرح الإشارات الأساسية.
تُختار شخصيات اللعبة سرًا حسب عدد اللاعبين، ولا يُعرف ما هي الشخصيات غير المستخدمة.'''),
  _InfoSection(Icons.nightlight_round, Color(0xFF9C27B0), 'مراحل اللعبة', '''
الليل: يغلق الجميع أعينهم، تُستخدم القدرات، تحدث القتلات، ويتلقى الأشرار معلوماتهم.
النهار: يتحاور اللاعبون، تُكشف المعلومات، وتُطرح الترشيحات والتصويت للإعدام.'''),
  _InfoSection(Icons.gavel, Color(0xFFFFB300), 'قواعد أساسية', '''
لكل لاعب شخصية سرية وانحياز: أزرق للخير، أحمر للشر.
القاعدة الذهبية: يمكنك قول ما تشاء في أي وقت.
لا تنظر إلى رموز الشخصيات الخاصة بالآخرين ولا إلى كتاب الأسرار.
الموت لا يُخرجك من اللعبة؛ تستمر بالمشاركة والفوز أو الخسارة مع فريقك، لكنك تفقد قدرتك، ولا يمكنك الترشيح، ويتبقى لك صوت واحد فقط لبقية اللعبة.
الترشيح: يمكن لكل لاعب حي ترشيح لاعب آخر مرة واحدة يوميًا. يُعدَم المرشَّح إذا حصل على أصوات تعادل نصف عدد الأحياء على الأقل وكان الأعلى تصويتًا. في حال التعادل، لا يُعدَم أحد.
الثمل والتسمم: لا تعمل قدرة اللاعب الثمل أو المسموم فعليًا، لكنه يعتقد أنها تعمل، وقد يحصل على معلومات خاطئة عمدًا.
بعض القدرات تعمل عند الموت أو بعده إذا نصّ عليها ذلك.
إذا تغيّرت شخصية اللاعب، يفقد قدرته القديمة فورًا ويكتسب الجديدة.'''),
  _InfoSection(Icons.groups, Color(0xFF00BCD4), 'أنواع الشخصيات', '''
القروي (Townsfolk): من الخير، وقدرته غالبًا معلومات أو حماية.
الدخيل (Outsider): من الخير، لكن قدرته قد تُعيق فريقه.
التابع (Minion): من الشر، وقدرته تساعد الغول.
الغول (Demon): من الشر، وموته يعني فوز الخير.
المسافر (Traveller): شخصية خاصة للاعبين المنضمين متأخرًا أو المغادرين مبكرًا، ويمكن نفيه من اللعبة دون إعدام.'''),
  _InfoSection(Icons.lightbulb_outline, Color(0xFFF44336), 'نصائح موجزة', '''
حدّد هدف شخصيتك منذ البداية، وشارك معلوماتك تدريجيًا لا دفعة واحدة.
كوّن تحالفات، واستمع للجميع أكثر مما تتحدث.
لا تخشَ الموت أو الإعدام إذا كان ذلك يخدم فريقك في النهاية.
إذا كنت شريرًا: اكذب بثبات، وادعم زملاءك الأشرار، وحاول تعطيل منطق الخير.
إذا كنت تابعًا: احمِ غولك، ولا تصوّت ضده إلا إذا كانت لديك خطة بديلة واضحة.
إذا كنت الغول: ابقَ حيًا، واختر ضحاياك بعناية وليس عشوائيًا.'''),
  _InfoSection(Icons.record_voice_over, Color(0xFF8FA69C),
      'إدارة اللعبة (لراوي القصة)', '''
حافظ على سرية المعلومات، وكن محايدًا دائمًا.
أيقظ اللاعبين بنقر خفيف على الكتف أو الركبة، وتحرك بهدوء بين المقاعد.
عند وقوع خطأ، لا تحاول "موازنة اللعبة" لصالح الطرف الخاسر — أخبر المجموعة أن خطأ حدث دون ذكر تفاصيله، واستمر باللعب.
أجب عن الأسئلة الحساسة سرًا مع اللاعب المعني فقط.
شجّع اللاعبين الخجولين على المشاركة، وأوقف أي سلوك سلبي أو غير محترم فورًا.
قرار راوي القصة نهائي عند أي التباس في القواعد.'''),
];

class _GlossaryTerm {
  final Color accent;
  final String term;
  final String body;
  const _GlossaryTerm(this.accent, this.term, this.body);
}

const _glossary = <_GlossaryTerm>[
  _GlossaryTerm(Color(0xFF9C27B0), 'مسموم (Poisoned)',
      'اللاعب المسموم لا يملك قدرته فعليًا، لكنه لا يعرف ذلك ويتصرف — ويجيب حافظ الأسرار عنه — كأنه ما زال يملكها. أي معلومة يمنحها قد تكون خاطئة.'),
  _GlossaryTerm(Color(0xFFFF9800), 'ثمل (Drunk)',
      'مثل المسموم تمامًا من ناحية التأثير: لا تعمل قدرته، لكنه يعتقد أنها تعمل. هذه حالة دائمة طوال اللعبة لدى شخصية "السكير".'),
  _GlossaryTerm(Color(0xFF00E39B), 'سليم (Healthy)',
      'غير ثمل وغير مسموم — قدرة اللاعب تعمل بشكل طبيعي وصحيح.'),
  _GlossaryTerm(Color(0xFFE91E63), 'مجنون (Mad)',
      'بعض الشخصيات "تُجنَّن" بمعتقد معين. إذا لم يتظاهر اللاعب بأن هذا المعتقد صحيح، قد يُعرّضه ذلك للإعدام حسب نص قدرته.'),
  _GlossaryTerm(Color(0xFF2196F3), 'ترشيح (Nomination)',
      'اقتراح إعدام لاعب معين خلال النهار. كل لاعب حي يمكنه الترشيح مرة واحدة في اليوم، وكل لاعب يمكن ترشيحه مرة واحدة في اليوم.'),
  _GlossaryTerm(Color(0xFFF44336), 'إعدام (Execution)',
      'القرار الجماعي بقتل اللاعب المرشح، بعد تصويت الجميع. يحتاج المرشَّح أصواتًا تعادل نصف عدد الأحياء على الأقل ليُعدم.'),
  _GlossaryTerm(Color(0xFF616161), 'موت (Death)',
      'يحدث نهارًا بالإعدام، أو ليلًا بقدرات الشخصيات المختلفة.'),
  _GlossaryTerm(Color(0xFFFFC107), 'التضليلات (Bluffs)',
      'ثلاث شخصيات غير موجودة فعليًا في اللعبة، يعرفها الغول من الليلة الأولى ليدّعيها إن اضطر. الراوي أحيانًا يرسلها للاعبين أيضًا كأداة تضليل إضافية.'),
];

class GameInfoScreen extends StatefulWidget {
  const GameInfoScreen({super.key});
  @override
  State<GameInfoScreen> createState() => _GameInfoScreenState();
}

class _GameInfoScreenState extends State<GameInfoScreen> {
  int _tab = 0;
  List<ScriptCharacter>? _characters;

  @override
  void initState() {
    super.initState();
    ScriptLibrary.instance.loadAllOfficialCharacters().then((list) {
      if (mounted) setState(() => _characters = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Game Info')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.menu_book, size: 16),
                    label: Text('القواعد')),
                ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.style, size: 16),
                    label: Text('المصطلحات')),
                ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.theater_comedy, size: 16),
                    label: Text('الشخصيات')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              0 => _buildRules(),
              1 => _buildGlossary(),
              _ => _buildCharacters(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRules() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          // Pinned, always-visible win-condition summary — not
          // collapsible, since it's the single most important thing a
          // new player needs to know before anything else.
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0x332196F3), Color(0x33F44336)],
              ),
              border: Border.all(color: Colors.white24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كيف تنتهي اللعبة',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white)),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.shield, color: Color(0xFF2196F3), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('فوز الخير: بترشيح الغول وإعدامه.',
                          style: TextStyle(
                              color: Color(0xFF2196F3),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.whatshot, color: Color(0xFFF44336), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'فوز الشر: إذا بقي لاعبان فقط على قيد الحياة (دون احتساب المسافرين).',
                          style: TextStyle(
                              color: Color(0xFFF44336),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final s in _ruleSections)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: s.accent.withOpacity(0.35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: s.accent.withOpacity(0.16),
                        shape: BoxShape.circle),
                    child: Icon(s.icon, color: s.accent, size: 20),
                  ),
                  title: Text(s.title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: s.accent,
                          fontSize: 15)),
                  childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.body.trim(),
                        style: const TextStyle(height: 1.7, fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlossary() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _glossary.length,
        itemBuilder: (context, i) {
          final g = _glossary[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: g.accent.withOpacity(0.4), width: 1.2),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border(right: BorderSide(color: g.accent, width: 4)),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.term,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: g.accent)),
                  const SizedBox(height: 6),
                  Text(g.body,
                      style: const TextStyle(height: 1.6, fontSize: 13.5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharacters() {
    if (_characters == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final byTeam = <String, List<ScriptCharacter>>{};
    for (final c in _characters!) {
      byTeam.putIfAbsent(c.team, () => []).add(c);
    }
    return ListView(
      children: [
        for (final team in ScriptCharacter.teamOrder)
          if (byTeam[team]?.isNotEmpty == true) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(ScriptCharacter.teamLabel(team),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: teamColor(team))),
            ),
            for (final c in byTeam[team]!)
              ListTile(
                leading: CharacterAvatar(character: c, radius: 20),
                title: Text(c.name),
                subtitle: Text(c.ability,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => showCharacterAbilitySheet(context, c),
              ),
          ],
      ],
    );
  }
}
