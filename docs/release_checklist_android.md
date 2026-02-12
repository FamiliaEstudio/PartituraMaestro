# Checklist de publicação Android

## 0) Validar estrutura Android recriada

- `android/app/build.gradle` existe com:
  - `namespace = "com.partituramaestro.pastoral_pdf_organizer"`
  - `applicationId = "com.partituramaestro.pastoral_pdf_organizer"`
  - `signingConfigs.release` ativo
- `android/app/src/main/AndroidManifest.xml` com `android:label="Partitura Maestro"`
- `android/app/src/main/kotlin/com/partituramaestro/pastoral_pdf_organizer/MainActivity.kt` presente
- `android/key.properties` **não versionado** (definido no `android/.gitignore`)

## 1) Assinatura (keystore)

1. Gerar keystore de produção:
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Criar `android/key.properties` (não versionar):
   ```properties
   storePassword=***
   keyPassword=***
   keyAlias=upload
   storeFile=app/upload-keystore.jks
   ```
3. Confirmar que `signingConfigs.release` e `buildTypes.release` estão configurados no `android/app/build.gradle`.

## 2) Versionamento

1. Atualizar versão em `pubspec.yaml` no formato `x.y.z+build`.
2. Validar changelog interno e impacto de migração de banco.
3. Gerar binários de release:
   ```bash
   flutter build apk --release --dart-define=APP_FLAVOR=release
   flutter build appbundle --release --dart-define=APP_FLAVOR=release
   ```

## 3) Validações antes do envio

- `dart format --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`
- Smoke test manual em dispositivo Android real
- Revisar permissões e mensagens para armazenamento

## 4) Publicação na Play Console

1. Subir `.aab` na trilha interna.
2. Revisar crashes/ANRs iniciais.
3. Promover para produção após validação funcional.

## 5) Pós-release

- Monitorar erros de runtime (telemetria opcional habilitada em produção).
- Registrar hotfix se houver regressão crítica.


## 6) Go / No-Go (critério mínimo)

**Go** somente quando todos os itens abaixo estiverem OK:

- Build e análise estática sem erros:
  - `flutter analyze` limpo (zero erros)
- Suíte de testes verde:
  - `flutter test` 100% passando
- Verificação manual em Android 13+:
  - importar ao menos 1 PDF pela UI
  - abrir PDF importado após reiniciar o app
  - validar fluxo de relocalização quando o arquivo é movido/indisponível

**No-Go** se qualquer item acima falhar.
