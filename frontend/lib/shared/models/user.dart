import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String? avatarUrl;

  const User({required this.id, required this.username, this.avatarUrl});

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
}
