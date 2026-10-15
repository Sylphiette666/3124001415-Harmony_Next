import {cp,mkdir,access,rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
await access(resolve(root,'web/dist/index.html'));
const destination=resolve(root,'entry/src/main/resources/rawfile/atlas');
if(destination!==resolve(root,'entry','src','main','resources','rawfile','atlas'))throw new Error('Unexpected output path');
// Only the generated atlas directory is replaced, never course documents or user source.
await rm(destination,{recursive:true,force:true});
await mkdir(destination,{recursive:true});
await cp(resolve(root,'web/dist'),destination,{recursive:true});
console.log('Web distribution copied into ArkWeb rawfile assets.');
