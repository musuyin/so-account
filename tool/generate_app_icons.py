"""Resize the approved paperclip artwork into existing platform icon slots."""
import json
from pathlib import Path

from PIL import Image


def main():
    root = Path(__file__).resolve().parent.parent
    with Image.open(root / 'design/icons/paperclip-v1.png') as artwork:
        source = artwork.convert('RGB')
    outputs = {}
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        outputs[root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'] = size
    ios = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for entry in json.loads((ios / 'Contents.json').read_text())['images']:
        if 'filename' in entry:
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
            outputs[ios / entry['filename']] = size
    for filename, size in outputs.items():
        source.resize((size, size), Image.Resampling.LANCZOS).save(filename)
        with Image.open(filename) as icon:
            assert icon.size == (size, size) and icon.mode == 'RGB'
    print(f'Generated and checked {len(outputs)} opaque Android/iOS icons')


if __name__ == '__main__':
    main()
