import {createHash} from 'node:crypto';
import {cpSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = resolve(root, process.argv[2] || 'build/web');
const destination = resolve(root, 'hosting/mobile');
const read = name => readFileSync(resolve(source, name), 'utf8');
const entry = read('index.html');
const bootstrap = read('flutter_bootstrap.js');
const dartCode = read('main.dart.js');
const buildId = createHash('sha256').update(dartCode).update(bootstrap).digest('hex').slice(0, 16);

if (!entry.includes('<base href="/mobile/">') ||
    !entry.includes('src="flutter_bootstrap.js"') ||
    !bootstrap.includes('"mainJsPath":"main.dart.js"')) {
  throw Error('Expected a Flutter JavaScript build for /mobile/');
}
cpSync(source, destination, {recursive: true});
writeFileSync(resolve(destination, 'flutter_bootstrap.js'),
  bootstrap.replace('"mainJsPath":"main.dart.js"', `"mainJsPath":"main.dart.js?v=${buildId}"`));
writeFileSync(resolve(destination, 'index.html'),
  entry.replace('src="flutter_bootstrap.js"', `src="flutter_bootstrap.js?v=${buildId}"`));
console.log(`Staged mobile web build ${buildId}`);
