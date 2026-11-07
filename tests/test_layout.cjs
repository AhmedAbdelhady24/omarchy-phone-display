const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../Layout.js'),'utf8').replace('.pragma library',''),ctx);
const m=[{name:'DP-1',x:0,y:0,width:2560,height:1440}],p={width:720,height:1560};
for (const [x,y,expectedX,expectedY] of [[2600,0,2560,0],[-750,0,-720,0],[0,-1600,0,-1560],[0,1450,0,1440]]) {
 const actual=ctx.snap(m,p,x,y); assert.equal(actual.x,expectedX);assert.equal(actual.y,expectedY);assert(!ctx.overlaps({...actual,...p},m[0]));
}
const phone=ctx.phoneSize({resolution:'native',scale:'1.5',orientation:'auto'},'1080x2340','2340x1080@60');
assert.equal(phone.width,1560);assert.equal(phone.height,720);
assert.equal(ctx.validMonitors([{name:'<img src=x>',x:0,y:0,width:100,height:100}]).length,1);
assert.equal(ctx.validMonitors([{name:'bad',x:NaN,y:0,width:100,height:100}]).length,0);
const multi=m.concat([{name:'HDMI-1',x:2560,y:0,width:1920,height:1080}]);
for(let x=-2000;x<6000;x+=137)for(let y=-2000;y<3000;y+=173){let pos=ctx.snap(multi,p,x,y); assert(!multi.some(m=>ctx.overlaps({...pos,...p},m)));}
console.log('Layout snapping, orientation, and monitor validation passed.');
