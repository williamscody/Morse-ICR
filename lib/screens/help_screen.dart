import 'package:flutter/material.dart';

/// One entry in the Help screen's table of contents and the matching
/// body section below it -- [icon]/[color] are shared by both, per
/// Bill's request that the TOC entry and its section header read as
/// visibly "the same thing" when you jump between them.
class _HelpSection {
  const _HelpSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.paragraphs,
  });

  final String title;
  final IconData icon;
  final Color color;

  /// Rendered as separate blocks, in order. A paragraph starting with
  /// "- " is rendered as a bullet instead of plain body text.
  final List<String> paragraphs;
}

final List<_HelpSection> _helpSections = [
  _HelpSection(
    title: 'Getting Started',
    icon: Icons.flag_circle,
    color: Colors.blue,
    paragraphs: [
      'Morse ICR plays a Morse code character, then gives you a short '
          'window to answer -- by speaking or simply knowing it -- before '
          'the computer\'s voice announces the character out loud. '
          'Answering correctly before the computer does is "beating the '
          'computer," this app\'s core training mechanic.',
      'Tap Start on the main screen to begin a session. Tap Stop, or let '
          'an active Timer memory count down to zero, to end one.',
    ],
  ),
  _HelpSection(
    title: 'Character Speed, Recognition Time & Extra Gap',
    icon: Icons.speed,
    color: Colors.deepOrange,
    paragraphs: [
      '- Character Speed (WPM): how fast each Morse character is played, '
          'in words per minute.',
      '- Recognition Time: how long you have to answer before the '
          'computer announces the character for you. Shorter times make '
          'training harder.',
      '- Extra Gap: extra silence inserted before the next character '
          'starts. It does not affect whether you beat the computer -- it '
          'only gives Speech Recognition a little more breathing room to '
          'finish processing your answer before the next round begins.',
      'All three can be changed mid-session and take effect starting with '
          'the next character, never interrupting one already playing.',
    ],
  ),
  _HelpSection(
    title: 'Character Set & Focus',
    icon: Icons.grid_view_rounded,
    color: Colors.purple,
    paragraphs: [
      'The Character Set chips (A-Z, 0-9, Punct) choose which characters '
          'are trained. Multiple chips can be selected at once.',
      'The Focus button opens a full keyboard of every common Morse '
          'character. Tap characters on or off to build a custom practice '
          'list, then tap Done. A Focus list, once set, replaces the '
          'chips above entirely and stays active until you select a chip '
          'again or edit the Focus list. Clear removes every character '
          'from the list.',
      'On the Focus keyboard, each character is colored by your all-time '
          'performance with it: red means it\'s mostly been missed, green '
          'means mostly correct, with everything in between scaled '
          'against your best-performing character. A character with no '
          'color at all has never come up in a session yet.',
    ],
  ),
  _HelpSection(
    title: 'Timer',
    icon: Icons.timer_outlined,
    color: Colors.teal,
    paragraphs: [
      'The Timer row stores three duration memories and lets you select '
          'one as the active countdown for your next session. When the '
          'active timer reaches zero, the session stops automatically, '
          'the same as tapping Stop yourself.',
      'Tap the Timer row (only available when not training) to edit any '
          'memory\'s duration or change which one, if any, is selected. '
          'Selecting none turns the timer off.',
    ],
  ),
  _HelpSection(
    title: 'Training Log',
    icon: Icons.history,
    color: Colors.indigo,
    paragraphs: [
      'The clock-with-arrow icon at the top left opens the Training Log: '
          'every completed session, with its date, time, duration, and '
          'the character set or Focus list that was active.',
      'Each entry can be given free-form notes. The log also shows your '
          'cumulative training time, and can be cleared or exported as a '
          'CSV file via the share sheet.',
    ],
  ),
  _HelpSection(
    title: 'Voice & Speech Recognition',
    icon: Icons.record_voice_over,
    color: Colors.red,
    paragraphs: [
      'Voice controls whether the computer speaks each character\'s '
          'answer out loud once your Recognition Time expires.',
      'Speech Recognition listens for you speaking the answer and credits '
          'you if it hears you say it in time. It requires headphones '
          '(wired or Bluetooth). If Speech Recognition is on and no '
          'headphones are connected, the app will ask you to connect '
          'them or turn the toggle off.',
    ],
  ),
  _HelpSection(
    title: 'Punctuation Speaking',
    icon: Icons.abc,
    color: Colors.brown,
    paragraphs: [
      'Choose how the computer announces two punctuation characters: '
          '"." as either "Period" or "Dot", and "/" as either "Slash" or '
          '"Stroke".',
    ],
  ),
  _HelpSection(
    title: 'Morse & Voice Audio',
    icon: Icons.graphic_eq,
    color: Colors.green,
    paragraphs: [
      '- Morse Pitch: the tone frequency of the Morse code sidetone, in '
          'Hz.',
      '- Morse Volume: playback volume of the Morse tone.',
      '- Voice Volume: playback volume of the computer\'s spoken answer, '
          'independent of Morse Volume.',
    ],
  ),
  _HelpSection(
    title: 'Random Character Order',
    icon: Icons.shuffle,
    color: Colors.pink,
    paragraphs: [
      'When on (the default), characters are drawn randomly from the '
          'active set, with repeats allowed. Turning it off instead plays '
          'the active set\'s characters in a fixed, repeatable order -- '
          'useful mainly for isolating a specific accuracy issue rather '
          'than everyday training.',
    ],
  ),
  _HelpSection(
    title: 'Getting the Best Recognition Accuracy',
    icon: Icons.tips_and_updates,
    color: Colors.amber,
    paragraphs: [
      '- A quiet room helps. Recognition timing is judged from the '
          'moment your speech first rises above the room\'s background '
          'noise, so a noisy room can delay real detection or trigger a '
          'false one.',
      '- Speak clearly and promptly, at a consistent distance from the '
          'mic.',
      '- Faster settings (short Recognition Time, high Character Speed) '
          'leave less margin for error -- an on-time answer can '
          'occasionally miss by a few tens of milliseconds. That\'s an '
          'inherent tradeoff of fast settings, not a defect.',
      'A few limits are inherent to any speech recognizer and not fixable '
          'through settings: some letters simply sound alike when spoken '
          'in isolation (B/P, M/N, and similar pairs), and a letter '
          'occasionally gets missed entirely rather than misheard. If '
          'recognition ever stops working entirely for a whole session, '
          'that is worth reporting -- these smaller misses are not.',
    ],
  ),
];

/// The in-app Help page: a table of contents at the top whose entries
/// jump straight to the matching section below, each color-matched
/// between its TOC row and its section header (Bill's request,
/// 2026-08-30). Reached from the main screen's "circled i" icon, just
/// left of Settings.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final List<GlobalKey> _sectionKeys = [
    for (final _ in _helpSections) GlobalKey(),
  ];

  void _jumpTo(int index) {
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      // SelectionArea (not individual SelectableText widgets) makes
      // every Text descendant selectable at once and wires up the
      // platform-native copy popup on both iOS and Android for free --
      // Bill asked for help text to be copyable (2026-08-30). Plain
      // taps (the TOC entries' InkWell) are unaffected; only
      // long-press/drag starts a text selection.
      body: SelectionArea(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              // A plain Column in a SingleChildScrollView, not ListView
              // -- ListView's Sliver machinery only builds/mounts
              // children near the current viewport, so a GlobalKey on a
              // section scrolled off-screen has no currentContext yet
              // and Scrollable.ensureVisible in [_jumpTo] silently
              // no-ops for it. Every section here is always mounted
              // instead, which is fine for a bounded page like this one
              // (same pattern TrainingScreen's own main-screen scroll
              // already uses).
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Contents',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _helpSections.length; i++)
                      _TocEntry(
                        section: _helpSections[i],
                        onTap: () => _jumpTo(i),
                      ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _helpSections.length; i++) ...[
                      _HelpSectionView(
                        key: _sectionKeys[i],
                        section: _helpSections[i],
                      ),
                      const SizedBox(height: 32),
                    ],
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

class _TocEntry extends StatelessWidget {
  const _TocEntry({required this.section, required this.onTap});

  final _HelpSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: section.color.withValues(alpha: 0.18),
              foregroundColor: section.color,
              child: Icon(section.icon, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: section.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).disabledColor),
          ],
        ),
      ),
    );
  }
}

class _HelpSectionView extends StatelessWidget {
  const _HelpSectionView({super.key, required this.section});

  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: section.color.withValues(alpha: 0.18),
              foregroundColor: section.color,
              child: Icon(section.icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: section.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final paragraph in section.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              paragraph.startsWith('- ') ? '•  ${paragraph.substring(2)}' : paragraph,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}
