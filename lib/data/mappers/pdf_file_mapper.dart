import '../../models/pdf_file.dart';
import '../dtos/pdf_file_dto.dart';

class PdfFileMapper {
  static PdfFile toDomain(PdfFileDto dto) => PdfFile(
        id: dto.id,
        path: dto.path,
        title: dto.title,
        displayName: dto.displayName,
        uri: dto.uri,
        fileHash: dto.fileHash,
        tagIds: dto.tagIds,
      );

  static PdfFileDto toDto(PdfFile model) => PdfFileDto(
        id: model.id,
        path: model.path,
        title: model.title,
        displayName: model.displayName,
        uri: model.uri,
        fileHash: model.fileHash,
        tagIds: model.tagIds,
      );
}
