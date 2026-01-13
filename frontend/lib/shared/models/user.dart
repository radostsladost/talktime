import 'package:equatable/equatable.dart';
import 'package:talktime/features/profile/data/models/profile_privacy.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String? description;
  final String? avatarUrl;

  const User({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.description,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      avatarUrl: json['avatarUrl'],
    );
  }

  factory User.byId(String id) {
    return User(id: id, username: 'o', avatarUrl: '');
  }

  @override
  List<Object?> get props => [id, username, avatarUrl];

  User copyWith({String? username, String? description, String? avatarUrl}) {
    return User(
      id: id,
      username: username ?? this.username,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
