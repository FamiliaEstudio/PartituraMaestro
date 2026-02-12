class SubStructureSlotDto {
  const SubStructureSlotDto({required this.id, required this.name, required this.requiredTagIds});

  final String id;
  final String name;
  final List<String> requiredTagIds;
}

class StructureTemplateDto {
  const StructureTemplateDto({required this.id, required this.name, required this.slots});

  final String id;
  final String name;
  final List<SubStructureSlotDto> slots;
}
