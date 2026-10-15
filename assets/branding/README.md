# Identidade e abertura

`app_icon.png` é a marca compacta do aplicativo, com o símbolo B e a seta verde. `splash.png` é a arte de abertura original, que também é copiada para a Web.

Para atualizar os tamanhos de ícone Android, Windows e Web após substituir `app_icon.png`:

```powershell
python -m pip install Pillow
python tool/generate_branding.py
```

O script apenas redimensiona os assets aprovados e exporta PNG/ICO. A splash Flutter referencia a fonte no `pubspec.yaml`; a Web usa uma cópia exportada pelo mesmo script.
