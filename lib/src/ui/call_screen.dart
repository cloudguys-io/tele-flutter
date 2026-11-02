import 'dart:async';

import 'package:flutter/material.dart';

import '../api/exception.dart';
import '../call/controller.dart';
import '../call/stage.dart';
import 'strings.dart';
import 'theme.dart';
import 'widgets.dart';

/// Text for a join error: Tele error codes get friendly messages (`too_early` is "This call isn't
/// open yet.").
String teleErrorText(TeleStrings s, Object? error, {String Function(DateTime)? formatTime}) {
  final code = error is TeleException ? error.code : null;
  switch (code) {
    case 'too_early':
      final opens = (error as TeleException).opensAt;
      if (opens == null) return s[TeleStringKey.tooEarly];
      final at = formatTime?.call(opens.toLocal()) ?? _hhmm(opens.toLocal());
      return '${s[TeleStringKey.tooEarly]} ${s.format(TeleStringKey.opensAt, {'time': at})}';
    case 'too_late' || 'call_ended':
      return s[TeleStringKey.callEnded];
    case 'call_cancelled':
      return s[TeleStringKey.callCancelled];
    case 'not_invited':
      return s[TeleStringKey.notInvited];
    case 'invite_expired' || 'invite_revoked' || 'invite_exhausted' || 'invite_not_found':
      return s[TeleStringKey.linkInvalid];
    case 'call_full':
      return s[TeleStringKey.callFull];
    case 'rate_limited':
      return s[TeleStringKey.rateLimited];
    default:
      return s[TeleStringKey.joinFailed];
  }
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Text for why the call ended.
String teleEndText(TeleStrings s, TeleEndReason reason) => s[switch (reason) {
      TeleEndReason.left => TeleStringKey.endedLeft,
      TeleEndReason.roomDeleted => TeleStringKey.endedRoomDeleted,
      TeleEndReason.duplicateIdentity => TeleStringKey.endedDuplicate,
      TeleEndReason.removed => TeleStringKey.endedRemoved,
      TeleEndReason.joinFailure => TeleStringKey.endedJoinFailure,
      TeleEndReason.disconnected => TeleStringKey.endedDisconnected,
      TeleEndReason.error => TeleStringKey.joinFailed,
    }];

/// A complete call screen: lobby with camera preview, the stage, controls, chat and notices.
///
/// The screen never sees your API key or secret: give it a [TeleCallController] built from a join
/// function (see [TeleCallController.invite]). [onLeave] runs when the user leaves or closes the
/// ended or error screen.
class TeleCallScreen extends StatefulWidget {
  const TeleCallScreen({
    super.key,
    required this.controller,
    this.onLeave,
    this.onEvent,
    this.language,
    this.strings,
    this.theme,
    this.title,
    this.displayName,
    this.lobby = true,
    this.chat = true,
    this.screenShare = true,
    this.devicePickers = true,
    this.recordingIndicator = true,
    this.extraControls = const [],
    this.formatTime,
  });

  final TeleCallController controller;

  /// The user left, or closed the ended or error screen.
  final void Function(TeleEndReason reason)? onLeave;

  /// Every call event (joined, participants, chat, left, failed).
  final void Function(TeleCallEvent event)? onEvent;

  /// `en` or `bn` (a tag like `bn-BD` uses `bn`). Defaults to the app's locale.
  final String? language;

  /// Per-label overrides on top of the language.
  final Map<TeleStringKey, String>? strings;

  /// Overrides the [TeleCallTheme] from the app theme.
  final TeleCallTheme? theme;

  /// Shown in the lobby, for example the invite preview's call title.
  final String? title;

  /// Shown in the lobby as "Joining as {name}". The name others see comes from the user token.
  final String? displayName;

  /// Without the lobby, the screen joins as soon as it is shown, with microphone and camera on.
  final bool lobby;
  final bool chat;
  final bool screenShare;
  final bool devicePickers;
  final bool recordingIndicator;

  /// Extra buttons for the control bar.
  final List<Widget> extraControls;
  final String Function(DateTime)? formatTime;

  @override
  State<TeleCallScreen> createState() => _TeleCallScreenState();
}

class _TeleCallScreenState extends State<TeleCallScreen> {
  StreamSubscription<TeleCallEvent>? _sub;

  TeleCallController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _subscribe();
    if (widget.lobby) {
      unawaited(c.startPreview());
    } else {
      unawaited(c.join());
    }
  }

  @override
  void didUpdateWidget(TeleCallScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      unawaited(_sub?.cancel());
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = c.events.listen((e) {
      widget.onEvent?.call(e);
      if (e is TeleCallLeft) widget.onLeave?.call(e.reason);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  TeleStrings get _strings => TeleStrings.of(
        widget.language ?? Localizations.maybeLocaleOf(context)?.languageCode,
        overrides: widget.strings,
      );

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final t = widget.theme ?? TeleCallTheme.of(context);
    return Theme(
      data: base.copyWith(
        extensions: [...base.extensions.values.where((e) => e is! TeleCallTheme), t],
        colorScheme: base.colorScheme.copyWith(primary: t.accent, onPrimary: t.onAccent, surface: t.surface, onSurface: t.text),
      ),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final s = _strings;
          return ColoredBox(
            color: t.background,
            child: SafeArea(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: t.text),
                child: switch (c.phase) {
                  TeleCallPhase.lobby => _Lobby(screen: widget, strings: s),
                  TeleCallPhase.joining => _Message(
                      text: s[TeleStringKey.joining],
                      busy: true,
                      actions: [_Action(s[TeleStringKey.leave], c.leave)],
                    ),
                  TeleCallPhase.live => _Live(screen: widget, strings: s),
                  TeleCallPhase.error => _Message(
                      text: teleErrorText(s, c.error, formatTime: widget.formatTime),
                      icon: Icons.error_outline,
                      actions: [_Action(s[TeleStringKey.tryAgain], c.retry, primary: true), _Action(s[TeleStringKey.exit], c.leave)],
                    ),
                  TeleCallPhase.ended => _Message(
                      text: teleEndText(s, c.endReason ?? TeleEndReason.disconnected),
                      icon: Icons.call_end,
                      actions: [
                        if (c.endReason != TeleEndReason.roomDeleted && c.endReason != TeleEndReason.removed)
                          _Action(s[TeleStringKey.rejoin], c.retry, primary: true),
                        _Action(s[TeleStringKey.exit], c.leave),
                      ],
                    ),
                  TeleCallPhase.left => _Message(text: teleEndText(s, TeleEndReason.left), icon: Icons.call_end),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.onPressed, {this.primary = false});
  final String label;
  final Future<void> Function() onPressed;
  final bool primary;
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.icon, this.busy = false, this.actions = const []});
  final String text;
  final IconData? icon;
  final bool busy;
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) CircularProgressIndicator(color: t.accent) else if (icon != null) Icon(icon, size: 40, color: t.muted),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: t.text))),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final a in actions)
                  a.primary
                      ? FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(teleMinTarget * 2, teleMinTarget), backgroundColor: t.accent, foregroundColor: t.onAccent),
                          onPressed: a.onPressed,
                          child: Text(a.label),
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(teleMinTarget * 2, teleMinTarget), foregroundColor: t.text),
                          onPressed: a.onPressed,
                          child: Text(a.label),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Lobby extends StatelessWidget {
  const _Lobby({required this.screen, required this.strings});
  final TeleCallScreen screen;
  final TeleStrings strings;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final c = screen.controller;
    final s = strings;
    final notice = c.notice;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(screen.title ?? s[TeleStringKey.readyToJoin],
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: t.text)),
              ),
              if (screen.displayName != null) ...[
                const SizedBox(height: 4),
                Text(s.format(TeleStringKey.joiningAs, {'name': screen.displayName!}),
                    textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
              ],
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  decoration: BoxDecoration(color: t.tile, borderRadius: BorderRadius.circular(t.radius)),
                  clipBehavior: Clip.antiAlias,
                  child: c.cameraEnabled && c.engine.previewTrack != null
                      ? TeleVideo(track: c.engine.previewTrack, name: screen.displayName ?? '', mirror: true)
                      : Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            TeleAvatar(name: screen.displayName ?? '', size: 72),
                            const SizedBox(height: 8),
                            if (!c.cameraEnabled) Text(s[TeleStringKey.cameraIsOff], style: TextStyle(color: t.muted)),
                          ]),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TeleControlButton(
                    icon: c.microphoneEnabled ? Icons.mic : Icons.mic_off,
                    label: s[c.microphoneEnabled ? TeleStringKey.micOn : TeleStringKey.micOff],
                    toggled: c.microphoneEnabled,
                    danger: !c.microphoneEnabled,
                    onPressed: c.toggleMicrophone,
                  ),
                  TeleControlButton(
                    icon: c.cameraEnabled ? Icons.videocam : Icons.videocam_off,
                    label: s[c.cameraEnabled ? TeleStringKey.cameraOn : TeleStringKey.cameraOff],
                    toggled: c.cameraEnabled,
                    danger: !c.cameraEnabled,
                    onPressed: c.toggleCamera,
                  ),
                  if (c.engine.canFlipCamera)
                    TeleControlButton(icon: Icons.cameraswitch, label: s[TeleStringKey.flipCamera], onPressed: c.flipCamera),
                ],
              ),
              if (screen.devicePickers) ...[
                const SizedBox(height: 8),
                TeleDevicePickers(controller: c, strings: s),
              ],
              if (notice != null) TeleBanner(text: s.format(notice.key, notice.vars), icon: Icons.info_outline),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(teleMinTarget + 4),
                  backgroundColor: t.accent,
                  foregroundColor: t.onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius)),
                ),
                onPressed: c.join,
                child: Text(s[TeleStringKey.joinCall], style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.screen, required this.strings});
  final TeleCallScreen screen;
  final TeleStrings strings;

  Future<void> _confirmEnd(BuildContext context) async {
    final s = strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s[TeleStringKey.confirmEndForAll]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s[TeleStringKey.cancel])),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s[TeleStringKey.endForAll])),
        ],
      ),
    );
    if (ok ?? false) await screen.controller.endForAll();
  }

  void _devices(BuildContext context) {
    final t = TeleCallTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TeleDevicePickers(controller: screen.controller, strings: strings),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final c = screen.controller;
    final s = strings;
    final notice = c.notice;
    final e = c.engine;

    final controls = Wrap(
      alignment: WrapAlignment.center,
      children: [
        TeleControlButton(
          icon: c.microphoneEnabled ? Icons.mic : Icons.mic_off,
          label: s[c.microphoneEnabled ? TeleStringKey.mute : TeleStringKey.unmute],
          toggled: c.microphoneEnabled,
          danger: !c.microphoneEnabled,
          onPressed: c.toggleMicrophone,
        ),
        TeleControlButton(
          icon: c.cameraEnabled ? Icons.videocam : Icons.videocam_off,
          label: s[c.cameraEnabled ? TeleStringKey.cameraTurnOff : TeleStringKey.cameraTurnOn],
          toggled: c.cameraEnabled,
          danger: !c.cameraEnabled,
          onPressed: c.toggleCamera,
        ),
        if (e.canFlipCamera && c.cameraEnabled)
          TeleControlButton(icon: Icons.cameraswitch, label: s[TeleStringKey.flipCamera], onPressed: c.flipCamera),
        if (!e.canSelectAudioOutput)
          TeleControlButton(
            icon: c.speakerphoneOn ? Icons.volume_up : Icons.hearing,
            label: s[c.speakerphoneOn ? TeleStringKey.speakerphoneOff : TeleStringKey.speakerphoneOn],
            toggled: c.speakerphoneOn,
            onPressed: () => c.setSpeakerphone(!c.speakerphoneOn),
          ),
        if (screen.screenShare && e.canShareScreen)
          TeleControlButton(
            icon: c.screenShareEnabled ? Icons.stop_screen_share : Icons.screen_share,
            label: s[c.screenShareEnabled ? TeleStringKey.stopSharing : TeleStringKey.shareScreen],
            toggled: c.screenShareEnabled,
            active: c.screenShareEnabled,
            onPressed: () => c.setScreenShare(!c.screenShareEnabled),
          ),
        TeleControlButton(
          icon: c.layout == TeleLayout.grid ? Icons.view_agenda_outlined : Icons.grid_view,
          label: s[c.layout == TeleLayout.grid ? TeleStringKey.layoutSpeaker : TeleStringKey.layoutGrid],
          onPressed: () => c.layout = c.layout == TeleLayout.grid ? TeleLayout.speaker : TeleLayout.grid,
        ),
        if (screen.devicePickers)
          TeleControlButton(icon: Icons.settings_outlined, label: s[TeleStringKey.devices], onPressed: () => _devices(context)),
        if (screen.chat)
          TeleControlButton(
            icon: Icons.chat_bubble_outline,
            label: c.unreadCount > 0
                ? '${s[TeleStringKey.chat]}, ${s.format(TeleStringKey.unread, {'count': c.unreadCount})}'
                : s[TeleStringKey.chat],
            active: c.chatOpen,
            toggled: c.chatOpen,
            badge: c.unreadCount,
            onPressed: () => c.chatOpen = !c.chatOpen,
          ),
        if (c.canRecord)
          TeleControlButton(
            icon: c.isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record_outlined,
            label: s[c.isRecording ? TeleStringKey.stopRecording : TeleStringKey.record],
            active: c.isRecording,
            onPressed: c.recordingBusy ? null : () => c.setRecording(!c.isRecording),
          ),
        ...screen.extraControls,
        if (c.canEndForAll)
          TeleControlButton(icon: Icons.cancel_presentation, label: s[TeleStringKey.endForAll], danger: true, onPressed: () => _confirmEnd(context)),
        TeleControlButton(icon: Icons.call_end, label: s[TeleStringKey.leave], danger: true, onPressed: c.leave),
      ],
    );

    final main = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(c.call?.title ?? '',
                    overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: t.text)),
              ),
              Text(s.format(TeleStringKey.inCall, {'count': c.participantCount}), style: TextStyle(color: t.muted)),
            ],
          ),
        ),
        if (screen.recordingIndicator && c.isRecording)
          TeleBanner(text: s[TeleStringKey.recording], icon: Icons.fiber_manual_record, color: t.danger),
        if (c.reconnecting) TeleBanner(text: s[TeleStringKey.reconnecting], icon: Icons.sync),
        if (notice != null)
          TeleBanner(
            text: s.format(notice.key, notice.vars),
            icon: Icons.info_outline,
            onDismiss: c.dismissNotice,
            dismissLabel: s[TeleStringKey.exit],
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TeleStageView(controller: c, strings: s),
          ),
        ),
        Padding(padding: const EdgeInsets.only(bottom: 8), child: controls),
      ],
    );

    return LayoutBuilder(builder: (context, box) {
      final chatOpen = screen.chat && c.chatOpen;
      final panel = TeleChatPanel(controller: c, strings: s, onClose: () => c.chatOpen = false);
      if (box.maxWidth >= 900) {
        return Row(children: [
          Expanded(child: main),
          if (chatOpen) ...[VerticalDivider(width: 1, color: t.line), SizedBox(width: 340, child: panel)],
        ]);
      }
      return Stack(children: [main, if (chatOpen) Positioned.fill(child: panel)]);
    });
  }
}
