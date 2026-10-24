"""Export the generated master unchanged in design, at standard app-icon sizes."""
from pathlib import Path
from PIL import Image
import json
r=Path(__file__).resolve().parents[1]
master=Image.open(r/'assets/images/interpreter-talk.png').convert('RGBA')
icons=r/'web/icons';icons.mkdir(parents=True,exist_ok=True)
for size in [192,512]:
 image=master.resize((size,size),Image.Resampling.LANCZOS)
 image.save(icons/f'Icon-{size}.png')
 image.save(icons/f'Icon-maskable-{size}.png')
master.resize((180,180),Image.Resampling.LANCZOS).save(icons/'apple-touch-icon.png')
master.resize((64,64),Image.Resampling.LANCZOS).save(r/'web/favicon.png')
master.save(r/'web/favicon.ico',sizes=[(16,16),(32,32),(48,48),(64,64)])
manifest=json.loads((r/'web/manifest.json').read_text(encoding='utf-8'))
manifest.update(name='통역톡 · Interpreter Talk',short_name='통역톡',lang='ko',id='.',
 background_color='#FFFFFF',theme_color='#3346B8',description='한국어·몽골어로 함께하는 통역톡 · Interpreter Talk')
(r/'web/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
p=r/'web/index.html';s=p.read_text(encoding='utf-8')
s=s.replace('<html>','<html lang="ko">').replace('content="bridgechat"','content="통역톡"')
s=s.replace('<link rel="manifest" href="manifest.json">','<link rel="manifest" href="manifest.json">\n  <meta name="theme-color" content="#3346B8">\n  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">')
s=s.replace('A new Flutter project.','통역톡 · Interpreter Talk — 한국어·몽골어 메신저')
p.write_text(s,encoding='utf-8')
print('Master, favicon, 192/512 app icons and Apple touch icon exported.')
