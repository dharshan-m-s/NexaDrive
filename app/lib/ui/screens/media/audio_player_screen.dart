import 'package:flutter/material.dart';
import '../../../../services/api.dart';
import '../../widgets/download_to_view.dart';

/// Audio viewer — downloads tracks for playback in the OS player when a media
/// backend is available; otherwise offers a clean download flow.
class AudioPlayerScreen extends DownloadToViewScreen {
  AudioPlayerScreen({super.key, required super.file, required Api api})
      : super(
          icon: Icons.music_note_rounded,
          subtitle: 'Download the track to play it with your device player.',
          downloader: api.downloadToFile,
        );
}