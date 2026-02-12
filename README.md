# PartituraMaestro

Projeto em Dart/Flutter para organização de partituras em PDF.

## Ambiente

```bash
flutter pub get
flutter run
```

## Flavors / Build config

O app usa `--dart-define` para controlar flavor e telemetria opcional:

- `APP_FLAVOR=debug` (padrão)
- `APP_FLAVOR=release`
- `ENABLE_CRASHLYTICS=true|false` (placeholder para integração real)

Exemplos:

```bash
flutter run --dart-define=APP_FLAVOR=debug
flutter run --release --dart-define=APP_FLAVOR=release --dart-define=ENABLE_CRASHLYTICS=true
```

## Qualidade

Pipeline CI em `.github/workflows/ci.yml` executa:

- `dart format --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`

## Publicação Android

Checklist de assinatura e versionamento: [`docs/release_checklist_android.md`](docs/release_checklist_android.md).
