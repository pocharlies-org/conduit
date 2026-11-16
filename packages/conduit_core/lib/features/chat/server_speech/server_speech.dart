import 'dart:typed_data';

/// Audio a backend synthesized, with the MIME type it reported.
typedef SynthesizedSpeech = ({Uint8List bytes, String mimeType});

/// Speech-to-text and text-to-speech run by the chat's own backend.
///
/// Audio only ever goes to the backend the chat belongs to: the Open WebUI
/// server.
abstract interface class ServerSpeechProvider {
  /// Whether [transcribe] is set up for this backend.
  bool get canTranscribe;

  /// Whether [synthesize] is set up for this backend.
  bool get canSynthesize;

  /// Whether the user picks among this backend's voices in Audio settings.
  bool get offersVoiceChoice;

  /// The text heard in [audio], or an empty string when no speech was heard.
  Future<String> transcribe(
    Uint8List audio, {
    required String fileName,
    required String mimeType,
    String? language,
  });

  /// [text] spoken aloud. [preferredVoice] is the voice picked in Audio
  /// settings and is used only when [offersVoiceChoice] is true.
  Future<SynthesizedSpeech> synthesize(
    String text, {
    String? preferredVoice,
    double? speed,
  });
}
