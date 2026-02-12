import '../../models/structure_template.dart';
import '../dtos/structure_template_dto.dart';

class StructureTemplateMapper {
  static StructureTemplate toDomain(StructureTemplateDto dto) {
    return StructureTemplate(
      id: dto.id,
      name: dto.name,
      slots: dto.slots
          .map((slot) => SubStructureSlot(id: slot.id, name: slot.name, requiredTagIds: slot.requiredTagIds))
          .toList(),
    );
  }

  static StructureTemplateDto toDto(StructureTemplate model) {
    return StructureTemplateDto(
      id: model.id,
      name: model.name,
      slots: model.slots
          .map((slot) => SubStructureSlotDto(id: slot.id, name: slot.name, requiredTagIds: slot.requiredTagIds))
          .toList(),
    );
  }
}
