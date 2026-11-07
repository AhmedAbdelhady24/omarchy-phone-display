const assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm'), path=require('node:path');
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../Colors.js'),'utf8').replace('.pragma library',''),ctx);
for(let r=0;r<=255;r+=17)for(let g=0;g<=255;g+=17)for(let b=0;b<=255;b+=17){
 const accent={r:r/255,g:g/255,b:b/255};
 const ink=ctx.inkFor(accent)==='#000000'?{r:0,g:0,b:0}:{r:1,g:1,b:1};
 assert(ctx.contrast(accent,ink)>=4.5,'Selected text needs readable contrast');
}
assert.equal(ctx.inkFor({r:0,g:0,b:0}),'#ffffff');
assert.equal(ctx.inkFor({r:1,g:1,b:1}),'#000000');
console.log('Accent text contrast passed for 4,096 light and dark colors.');
