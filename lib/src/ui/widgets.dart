import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack, VideoTrackRenderer, VideoViewFit, VideoViewMirrorMode;

import '../call/controller.dart';
import '../call/engine.dart';
import '../call/stage.dart';
import 'strings.dart';
import 'theme.dart';

/// Minimum touch target for every control.
const double teleMinTarget = 48;

/// A round control-bar button with a tooltip and a semantics label.
class TeleControlButton extends StatelessWidget {
  const TeleControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
    this.toggled,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Filled with the accent colour.
  final bool active;
  final bool danger;

  /// For toggles: announced as pressed or not.
  final bool? toggled;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final bg = danger ? t.danger : (active ? t.accent : t.surface);
    final fg = danger ? t.onDanger : (active ? t.onAccent : t.text);
    final button = Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: danger || active ? bg : t.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(dimension: teleMinTarget, child: Icon(icon, color: fg, size: 22)),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: badge != null && badge! > 0 ? '$label, $badge' : label,
      toggled: toggled,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: badge != null && badge! > 0
            ? Badge(label: Text('${badge! > 99 ? '99+' : badge}'), backgroundColor: t.accent, textColor: t.onAccent, child: button)
            : button,
      ),
    );
  }
}

/// Initials for an avatar.
String teleInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = String.fromCharCodes(parts.first.runes.take(1));
  final last = parts.length > 1 ? String.fromCharCodes(parts.last.runes.take(1)) : '';
  return (first + last).toUpperCase();
}

class TeleAvatar extends StatelessWidget {
  const TeleAvatar({super.key, required this.name, this.size = 64});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
        child: Text(teleInitials(name), style: TextStyle(color: t.accent, fontSize: size * 0.36, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A video if there is a track, else an avatar.
class TeleVideo extends StatelessWidget {
  const TeleVideo({super.key, required this.track, required this.name, this.mirror = false, this.contain = false});
  final VideoTrack? track;
  final String name;
  final bool mirror;
  final bool contain;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return Center(child: TeleAvatar(name: name));
    return VideoTrackRenderer(
      t,
      fit: contain ? VideoViewFit.contain : VideoViewFit.cover,
      mirrorMode: mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
    );
  }
}

/// One participant's camera or screen share, with a name label and a pin button.
class TeleTileView extends StatelessWidget {
  const TeleTileView({
    super.key,
    required this.tile,
    required this.strings,
    required this.pinned,
    required this.speaking,
    required this.onTogglePin,
    this.canPin = true,
  });

  final TeleTile tile;
  final TeleStrings strings;
  final bool pinned;
  final bool speaking;
  final bool canPin;
  final VoidCallback onTogglePin;

  String get label {
    final p = tile.participant;
    final s = strings;
    var name = p.isLocal ? '${p.name}${s[TeleStringKey.youSuffix]}' : p.name;
    if (tile.screen) name += s[TeleStringKey.screenSuffix];
    if (!tile.screen && !p.microphoneEnabled) name += s[TeleStringKey.mutedSuffix];
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final p = tile.participant;
    final track = tile.screen ? p.screenShareTrack : p.cameraTrack;
    final pinLabel = strings.format(pinned ? TeleStringKey.unpin : TeleStringKey.pin, {'name': p.name});
    return Semantics(
      container: true,
      label: label,
      selected: pinned,
      child: GestureDetector(
        onDoubleTap: canPin ? onTogglePin : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: t.tile,
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(
              color: speaking ? t.accent : (pinned ? t.text.withValues(alpha: 0.5) : Colors.transparent),
              width: 3,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TeleVideo(
                track: track,
                name: p.name,
                mirror: p.isLocal && !tile.screen,
                contain: tile.screen,
              ),
              Positioned(
                left: 8,
                bottom: 8,
                right: 8,
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(t.radius / 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!tile.screen && !p.microphoneEnabled)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.mic_off, size: 14, color: Colors.white),
                              ),
                            Flexible(
                              child: ExcludeSemantics(
                                child: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canPin)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    button: true,
                    toggled: pinned,
                    label: pinLabel,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: pinLabel,
                      excludeFromSemantics: true,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTogglePin,
                          child: SizedBox.square(
                            dimension: teleMinTarget,
                            child: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large tile with a strip, or an even grid.
class TeleStageView extends StatelessWidget {
  const TeleStageView({super.key, required this.controller, required this.strings});
  final TeleCallController controller;
  final TeleStrings strings;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    final speaking = controller.participants.where((p) => p.isSpeaking).map((p) => p.identity).toSet();
    final all = [?stage.focus, ...stage.rest];
    final canPin = all.length > 1;
    Widget tile(TeleTile t) => TeleTileView(
          key: ValueKey(t.key),
          tile: t,
          strings: strings,
          pinned: controller.pinned == t.key,
          speaking: !t.screen && speaking.contains(t.participant.identity),
          canPin: canPin,
          onTogglePin: () => controller.togglePinned(t.key),
        );

    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final focus = stage.focus;
      if (focus != null) {
        final wide = box.maxWidth >= 900;
        final strip = ListView.separated(
          scrollDirection: wide ? Axis.vertical : Axis.horizontal,
          itemCount: stage.rest.length,
          separatorBuilder: (_, _) => const SizedBox.square(dimension: gap),
          itemBuilder: (_, i) => AspectRatio(aspectRatio: 16 / 10, child: tile(stage.rest[i])),
        );
        final children = <Widget>[
          Expanded(child: tile(focus)),
          if (stage.rest.isNotEmpty) ...[
            const SizedBox.square(dimension: gap),
            SizedBox(width: wide ? 260 : null, height: wide ? null : 120, child: strip),
          ],
        ];
        return wide ? Row(children: children) : Column(children: children);
      }
      final n = stage.rest.length;
      if (n == 0) return const SizedBox.shrink();
      final portrait = box.maxHeight > box.maxWidth;
      var cols = 1;
      while (cols * cols < n) {
        cols++;
      }
      if (portrait && n > 1) cols = n <= 2 ? 1 : (n <= 6 ? 2 : 3);
      final rows = (n / cols).ceil();
      return Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    Expanded(child: r * cols + c < n ? tile(stage.rest[r * cols + c]) : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Dropdowns for microphone, camera and (where the platform allows) speaker.
class TeleDevicePickers extends StatefulWidget {
  const TeleDevicePickers({super.key, required this.controller, required this.strings});
  final TeleCallController controller;
  final TeleStrings strings;

  @override
  State<TeleDevicePickers> createState() => _TeleDevicePickersState();
}

class _TeleDevicePickersState extends State<TeleDevicePickers> {
  List<TeleMediaDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.controller.devices();
      if (mounted) setState(() => _devices = d);
    } catch (_) {
      // No device list on this platform; the pickers stay hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final s = widget.strings;
    final kinds = [
      (TeleMediaKind.audioInput, s[TeleStringKey.microphone], Icons.mic_none),
      (TeleMediaKind.videoInput, s[TeleStringKey.camera], Icons.videocam_outlined),
      if (widget.controller.engine.canSelectAudioOutput) (TeleMediaKind.audioOutput, s[TeleStringKey.speaker], Icons.volume_up_outlined),
    ];
    final pickers = <Widget>[];
    for (final (kind, label, icon) in kinds) {
      final list = _devices.where((d) => d.kind == kind).toList();
      if (list.length < 2) continue;
      final selected = list.where((d) => d.selected).firstOrNull ?? list.first;
      pickers.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DropdownButtonFormField<TeleMediaDevice>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: t.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.radius / 2)),
          ),
          items: [
            for (final d in list)
              DropdownMenuItem(value: d, child: Text(d.label.isEmpty ? s[TeleStringKey.defaultDevice] : d.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (d) async {
            if (d == null) return;
            await widget.controller.selectDevice(d, label: label);
            await _load();
          },
        ),
      ));
    }
    if (pickers.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: pickers);
  }
}

/// The chat panel: history, live messages and an input.
class TeleChatPanel extends StatefulWidget {
  const TeleChatPanel({super.key, required this.controller, required this.strings, this.onClose});
  final TeleCallController controller;
  final TeleStrings strings;
  final VoidCallback? onClose;

  @override
  State<TeleChatPanel> createState() => _TeleChatPanelState();
}

class _TeleChatPanelState extends State<TeleChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.controller.sendChat(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final s = widget.strings;
    final messages = widget.controller.messages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    return Material(
      color: t.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(s[TeleStringKey.chat], style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: s[TeleStringKey.closeChat],
                    constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
                    icon: Icon(Icons.close, color: t.text),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(s[TeleStringKey.chatEmpty], textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(message: messages[i], youLabel: s[TeleStringKey.you]),
                  ),
          ),
          Divider(height: 1, color: t.line),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 4000,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(color: t.text),
                    decoration: InputDecoration(
                      hintText: s[TeleStringKey.message],
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.radius)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: s[TeleStringKey.send],
                  constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
                  style: IconButton.styleFrom(backgroundColor: t.accent, foregroundColor: t.onAccent),
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.youLabel});
  final TeleChatEntry message;
  final String youLabel;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final m = message;
    final who = m.mine ? youLabel : m.name;
    return Semantics(
      label: '$who: ${m.body}',
      excludeSemantics: true,
      child: Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(who, style: TextStyle(color: t.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: m.mine ? t.accent : t.tile,
                    borderRadius: BorderRadius.circular(t.radius * 0.75),
                  ),
                  child: SelectableText(m.body, style: TextStyle(color: m.mine ? t.onAccent : t.text)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line banner (recording, reconnecting, device problems).
class TeleBanner extends StatelessWidget {
  const TeleBanner({super.key, required this.text, required this.icon, this.color, this.onDismiss, this.dismissLabel});
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final c = color ?? t.text;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        padding: EdgeInsets.fromLTRB(12, onDismiss == null ? 10 : 0, 0, onDismiss == null ? 10 : 0),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(t.radius / 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: t.text))),
            if (onDismiss != null)
              IconButton(
                tooltip: dismissLabel,
                constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
                icon: Icon(Icons.close, size: 18, color: t.muted),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
