class TagDto {
  const TagDto({required this.id, required this.name});

  final String id;
  final String name;

  factory TagDto.fromMap(Map<String, Object?> map) {
    return TagDto(id: map['id'] as String, name: map['name'] as String);
  }

  Map<String, Object?> toMap() => {'id': id, 'name': name};
}
