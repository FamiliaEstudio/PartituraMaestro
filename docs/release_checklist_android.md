# Checklist de publicação Android

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
3. Configurar `signingConfigs.release` e `buildTypes.release` no `android/app/build.gradle`.

## 2) Versionamento

1. Atualizar versão em `pubspec.yaml` no formato `x.y.z+build`.
2. Validar changelog interno e impacto de migração de banco.
3. Conferir `flutter build appbundle --release` com flavor de release:
   ```bash
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
