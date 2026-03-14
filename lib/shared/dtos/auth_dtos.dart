/// Abstract base for DTOs to enforce toJson
abstract class BaseDto {
  Map<String, dynamic> toJson();
}

/// Login Request payload
class LoginRequestDto implements BaseDto {
  final String email;
  final String password;

  const LoginRequestDto({required this.email, required this.password});

  @override
  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

/// Signup Request payload
class SignupRequestDto implements BaseDto {
  final String email;
  final String password;
  final String? name;

  const SignupRequestDto({
    required this.email,
    required this.password,
    this.name,
  });

  @override
  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    if (name != null) 'name': name,
  };
}

/// Base Auth Response
class AuthResponseDto {
  final String token;
  final String userId;
  final String? email;
  final String? name;

  const AuthResponseDto({
    required this.token,
    required this.userId,
    this.email,
    this.name,
  });

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) {
    return AuthResponseDto(
      token: json['token'] as String? ?? json['access_token'] as String? ?? '',
      userId: json['user_id'] as String? ?? json['userId'] as String? ?? '',
      email: json['email'] as String?,
      name: json['name'] as String?,
    );
  }
}
