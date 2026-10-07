"""Exporta tamanhos de plataforma a partir do ícone aprovado (Pillow)."""
from pathlib import Path
from shutil import copyfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'assets/branding/app_icon.png').convert('RGB')


def export(relative, size):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(target)


for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                      ('xxhdpi', 144), ('xxxhdpi', 192)]:
    export(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
    export(f'android/app/src/main/res/drawable-{density}/splash_icon.png', size * 4)
    # Camada de 108 dp com o símbolo dentro da área segura de 66 dp.
    export(f'android/app/src/main/res/drawable-{density}/launcher_foreground.png',
           round(size * 108 / 48))

for size in (192, 512):
    export(f'web/icons/Icon-{size}.png', size)
    export(f'web/icons/Icon-maskable-{size}.png', size)
export('web/favicon.png', 32)
copyfile(ROOT / 'assets/branding/splash.png', ROOT / 'web/splash.png')
source.save(ROOT / 'windows/runner/resources/app_icon.ico',
            sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
