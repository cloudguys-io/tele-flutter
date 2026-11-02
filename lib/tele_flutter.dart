/// Tele for Flutter: a REST client for the Tele API acting as the signed-in user, and a prebuilt
/// call screen on `livekit_client`.
library;

export 'src/api/client.dart';
export 'src/api/exception.dart';
export 'src/api/models.dart' hide Json;
export 'src/call/controller.dart';
export 'src/call/engine.dart';
export 'src/call/livekit_engine.dart' show LiveKitCallEngine, disconnectCauseOf, rtcConfigurationFor, teleChatTopic;
export 'src/call/stage.dart';
export 'src/ui/call_screen.dart' show TeleCallScreen, teleEndText, teleErrorText;
export 'src/ui/strings.dart' show TeleStringKey, TeleStrings;
export 'src/ui/theme.dart';
// Building blocks for a custom call UI; the other widgets in src/ are internal.
export 'src/ui/widgets.dart' show TeleChatPanel, TeleDevicePickers, TeleStageView;
