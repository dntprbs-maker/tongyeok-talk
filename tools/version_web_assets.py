"""Run after flutter build web to prevent stale JS on static Pages hosting."""
from pathlib import Path
import hashlib,re
root=Path(__file__).resolve().parents[1]
out=root/'docs'
code=(out/'main.dart.js').read_bytes()
version=hashlib.sha256(code).hexdigest()[:12]
main_name=f'main.{version}.dart.js'
(out/main_name).write_bytes(code)
bootstrap=(out/'flutter_bootstrap.js').read_text(encoding='utf-8').replace('"mainJsPath":"main.dart.js"',f'"mainJsPath":"{main_name}"')
boot_name=f'flutter_bootstrap.{version}.js'
(out/boot_name).write_text(bootstrap,encoding='utf-8')
index=(out/'index.html').read_text(encoding='utf-8')
index=re.sub(r'src="flutter_bootstrap(?:\.[a-f0-9]+)?\.js"',f'src="{boot_name}"',index)
(out/'index.html').write_text(index,encoding='utf-8')
(out/'.nojekyll').touch()
(out/'LICENSE.md').write_bytes((root/'LICENSE.md').read_bytes())
print(f'Versioned public bundle: {version}')
