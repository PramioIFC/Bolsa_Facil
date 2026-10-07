# Identidade e abertura

`splash.png` é a imagem original enviada pelo usuário. `app_icon.png` foi adaptado com a ferramenta integrada ImageGen para exibir apenas o símbolo em tamanhos pequenos.

Prompt usado: preservar a silhueta do B violeta e a seta verde da referência; remover o texto; aumentar a clareza; centralizar em fundo quase preto, com o símbolo nos 60% centrais e margem para máscaras circulares; sem moldura externa.

Para atualizar os tamanhos de Android, Windows e Web após substituir as fontes:

```powershell
python -m pip install Pillow
python tool/generate_branding.py
```

O script apenas redimensiona os assets aprovados e exporta PNG/ICO. A splash Flutter referencia a fonte no `pubspec.yaml`; a Web usa uma cópia exportada pelo mesmo script.
