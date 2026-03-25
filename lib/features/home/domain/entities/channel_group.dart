import 'package:equatable/equatable.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class ChannelGroup extends Equatable {
  final String name;
  final List<ChannelEntity> channels;

  const ChannelGroup({
    required this.name,
    required this.channels,
  });

  int get count => channels.length;

  @override
  List<Object?> get props => [name, channels];
}
