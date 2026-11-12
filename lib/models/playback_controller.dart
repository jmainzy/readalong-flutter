import 'package:just_audio/just_audio.dart' as just_audio;

/// Controls external audio or video synchronized with a ReadAlong document.
///
/// Implement this interface to connect the ReadAlong controls and sentence
/// highlighting to a player such as Vimeo, YouTube, or a custom media player.
/// The caller owns the controller and is responsible for disposing it.
abstract interface class PlaybackController {
  Duration get position;
  Duration? get duration;
  double get speed;
  PlayerState get state;

  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlayerState> get stateStream;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
}

/// Encapsulates the playing and processing states. Mirrors JustAudio
class PlayerState {
  /// Whether the player will play when [processingState] is
  /// [ProcessingState.ready].
  final bool playing;

  /// The current processing state of the player.
  final ProcessingState processingState;

  PlayerState(this.playing, this.processingState);

  @override
  String toString() => 'playing=$playing,processingState=$processingState';

  @override
  int get hashCode => Object.hash(playing, processingState);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is PlayerState &&
      other.playing == playing &&
      other.processingState == processingState;

  factory PlayerState.fromJustAudio(just_audio.PlayerState state) {
    return PlayerState(
      state.playing,
      switch (state.processingState) {
        just_audio.ProcessingState.idle => ProcessingState.idle,
        just_audio.ProcessingState.loading => ProcessingState.loading,
        just_audio.ProcessingState.buffering => ProcessingState.buffering,
        just_audio.ProcessingState.ready => ProcessingState.ready,
        just_audio.ProcessingState.completed => ProcessingState.completed,
      },
    );
  }
}

/// Enumerates the different processing states of a player.
enum ProcessingState {
  /// The player has not loaded an [AudioSource].
  idle,

  /// The player is loading an [AudioSource].
  loading,

  /// The player is buffering audio and unable to play.
  buffering,

  /// The player is has enough audio buffered and is able to play.
  ready,

  /// The player has reached the end of the audio.
  completed,
}