import 'package:equatable/equatable.dart';

/// Un programme TV issu du guide XMLTV.
class EpgProgramme extends Equatable {
  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;

  const EpgProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
  });

  // Progression (0..1) du programme en cours à l'instant [now].
  double progressAt(DateTime now) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    final done = now.difference(start).inSeconds;
    return (done / total).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [channelId, start, stop, title];
}

/// Programme en cours + suivant pour une chaîne donnée.
class EpgNowNext {
  final EpgProgramme? now;
  final EpgProgramme? next;
  const EpgNowNext({this.now, this.next});

  bool get isEmpty => now == null && next == null;
}
