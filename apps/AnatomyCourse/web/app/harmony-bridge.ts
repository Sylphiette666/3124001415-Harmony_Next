import type {Atlas, Concept} from './anatomy';
export const ALIASES: Record<string,string> = {'心脏':'heart','脑':'brain','肝':'liver','胃':'stomach','脾':'spleen','胰腺':'pancreas','膀胱':'urinary bladder','气管':'trachea','股骨':'femur','肾':'kidney','肺':'lung','肋骨':'rib','颅骨':'skull','肱骨':'humerus'};
export function searchAtlas(atlas:Atlas, query:string):Concept[] {
 const q=query.trim().toLowerCase(); if(!q)return [];
 const term=ALIASES[q]??q;
 return atlas.concepts.filter(c=>c.name.toLowerCase().includes(term)||c.id.toLowerCase()===term)
  .sort((a,b)=>Number(b.name.toLowerCase()===term)-Number(a.name.toLowerCase()===term)||a.name.length-b.name.length).slice(0,80);
}
export interface AtlasAPI {search:(q:string)=>Concept[];select:(id:string)=>boolean;isolate:(value:boolean)=>void;reset:()=>void}
declare global {interface Window {NativeAtlas?:{onEvent:(json:string)=>void};HarmonyAtlas?:AtlasAPI}}
export function postNative(type:string, payload:object={}) {try {window.NativeAtlas?.onEvent(JSON.stringify({type,...payload}));}catch{/* Standalone Web remains usable. */}}
export function attachBridge(atlas:Atlas, choose:(concept:Concept)=>void, isolate:(value:boolean)=>void, reset:()=>void) {
 window.HarmonyAtlas={search:q=>searchAtlas(atlas,q),select:id=>{
  const c=atlas.concepts.find(c=>c.id===id);
  const p=atlas.parts.find(p=>p.id===id);
  if(!c&&!p)return false;
  choose(c??{id:p!.conceptId,name:p!.name,elements:[p!.id]});return true;
 },isolate,reset};postNative('ready',{count:atlas.parts.length});
 return ()=>{delete window.HarmonyAtlas;};
}
