import '../../models/tag.dart';
import '../dtos/tag_dto.dart';

class TagMapper {
  static Tag toDomain(TagDto dto) => Tag(id: dto.id, name: dto.name);

  static TagDto toDto(Tag model) => TagDto(id: model.id, name: model.name);
}
