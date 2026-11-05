const fs=require('fs'),vm=require('vm'),assert=require('assert');
const load=f=>{const c={};vm.createContext(c);vm.runInContext(fs.readFileSync('product/payload/apps/papercalc/'+f,'utf8'),c);return c;};
const C=load('calc.js'),O=load('office.js');let checks=0;
function close(a,b){assert(Math.abs(a-b)<1e-9*Math.max(1,Math.abs(b)),`${a} != ${b}`);checks++;}
function office(keys){let s=O.fresh();for(const k of keys)s=O.press(s,k);assert(!s.error,s.error);return s;}
function keystr(str){return str.split(' ');}
for(const [s,v] of [['2+3×4',14],['2^3^2',512],['-2^2',-4],['sin(30)',.5],['sqrt(81)',9],['5!',120],['ln(e)',1]]){const r=C.calculate(s);assert(r.ok,r.text);close(r.value,v);}
close(C.calculate('x^2-4',{x:3}).value,5);close(C.calculate('sin(x)',{x:Math.PI/2,angleMode:'RAD'}).value,1);
for(const s of ['1/0','ln(0)','sqrt(-1)','171!','1;process.exit()','x.constructor','tan(90)']){assert(!C.calculate(s).ok,s);checks++;}
close(+office(keystr('2 + 3 × 4 =')).input,20);
close(+office(keystr('1 0 0 + 1 0 % =')).input,110);
close(+office(keystr('2 0 0 − 1 0 % =')).input,180);
close(+office(keystr('2 0 0 × 1 0 % =')).input,20);
close(+office(keystr('2 + 3 = = =')).input,11);
close(+office(keystr('5 M+ 3 M− MR')).input,2);
close(+office(keystr('5 M+ AC MR')).input,5);
close(+office(keystr('1 + 2 = 4 + 5 = GT')).input,12);
assert(O.press(office(keystr('1 ÷ 0')),'=').error);checks++;
close(C.rootBetween('x^2-4',0,3,'RAD'),2);
assert.strictEqual(C.rootBetween('1/x',-.9,1,'RAD'),null);checks++;
const points=C.sample('1/x',-1,1,101,'RAD');assert.strictEqual(points[50].y,null);checks++;
assert(C.sample('sqrt(x)',-10,10,101,'RAD').slice(0,50).every(p=>p.y===null));checks++;
console.log(`${checks} engine checks passed`);

function receipt(keys, expected){assert.strictEqual(office(keys).tape,expected);checks++;}
receipt(Array.from('12.50+8.20+3.00='),'12.50 + 8.20 + 3.00 = 23.7');
receipt(Array.from('12.50+8.20+3.00'),'12.50 + 8.20 + 3.00');
receipt(keystr('1 2 + 9 ⌫ 3 + 4 CE 5 ='),'12 + 3 + 5 = 20');
receipt(keystr('2 + × 3 ='),'2 × 3 = 6');
receipt(keystr('2 + 3 × 4 ='),'2 + 3 × 4 = 20');
receipt(keystr('2 + 3 = ='),'5 + 3 = 8');
receipt(keystr('2 + 3 = 4 + 5 ='),'4 + 5 = 9');
receipt(keystr('2 + 3 = + 4 ='),'5 + 4 = 9');
receipt(keystr('2 + 3 AC 4'),'4');
console.log('9 full receipt checks passed');
