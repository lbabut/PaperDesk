// Immediate execution, as on a desk calculator. No expression evaluation.
function fresh() { return {input:'0', left:0, op:'', entry:true, repeat:'', operand:0, memory:0, total:0, error:'', record:'', chain:'', tape:'', finished:false}; }
function number(n) { if(!isFinite(n))throw Error('Result outside range');return String(Number(n.toPrecision(12))); }
function apply(a,op,b) {
    if(op==='÷' && b===0)throw Error('Cannot divide by zero');
    return op==='+'?a+b:op==='−'?a-b:op==='×'?a*b:a/b;
}
function step(state,key) {
    var s=JSON.parse(JSON.stringify(state));s.record='';
    if(s.finished && /^[0-9.]$|^(CE|⌫|MR|GT|±|√|%)$/.test(key)){s.chain='';s.tape='';s.finished=false;}
    try {
        if(key==='AC'){var old=s;s=fresh();s.memory=old.memory;return s;}
        if(key==='MC'){s.memory=0;return s;}
        if(key==='GT'){s.input=number(s.total);s.entry=true;return s;}
        if(s.error && !/^[0-9.]$/.test(key) && key!=='CE')return s;
        if(s.error){s.error='';s.input='0';s.entry=true;}
        if(/^[0-9.]$/.test(key)) {
            if(s.entry){s.input=key==='.'?'0.':key;s.entry=false;}
            else if(key==='.' && s.input.indexOf('.')>=0)return s;
            else if(s.input.replace(/[-.]/g,'').length<12)s.input=s.input==='0'&&key!=='.'?key:s.input+key;
            return s;
        }
        var n=Number(s.input);
        if(key==='CE'){s.input='0';s.entry=false;}
        else if(key==='⌫'){s.input=s.input.length>1?s.input.slice(0,-1):'0';if(s.input==='-')s.input='0';s.entry=false;}
        else if(key==='±'){s.input=number(-n);}
        else if(key==='MR'){s.input=number(s.memory);s.entry=false;}
        else if(key==='M+' || key==='M−'){s.memory=Number(number(s.memory+(key==='M+'?n:-n)));s.entry=true;}
        else if(key==='√'){if(n<0)throw Error('Square root requires a number ≥ 0');s.input=number(Math.sqrt(n));s.entry=true;}
        else if(key==='%'){s.input=number((s.op==='+'||s.op==='−')?s.left*n/100:n/100);s.entry=false;}
        else if(['+','−','×','÷'].indexOf(key)>=0){
            if(s.op){
                if(!s.entry)s.chain+=s.input+' '+key+' ';
                else s.chain=s.chain.replace(/[+−×÷] $/,key+' ');
            } else s.chain=s.input+' '+key+' ';
            s.finished=false;
            if(s.op && !s.entry)s.input=number(apply(s.left,s.op,n));
            s.left=Number(s.input);s.op=key;s.entry=true;s.repeat='';
        }
        else if(key==='='){
            var entered=s.input, op=s.op||s.repeat, a=s.op?s.left:n, b=s.op?n:s.operand;
            if(op){s.input=number(apply(a,op,b));s.record=(s.op?s.chain+entered:number(a)+' '+op+' '+number(b))+' = '+s.input;s.tape=s.record;s.finished=true;s.chain='';s.repeat=op;s.operand=b;s.total=Number(number(s.total+Number(s.input)));}
            s.op='';s.entry=true;
        }
    } catch(e){s.error=e.message;s.op='';s.repeat='';s.entry=true;}
    return s;
}

// Keep the receipt separate from the numeric accumulator: intermediate sums
// must never replace the amounts originally entered. Display updates stay paced.
function press(state,key) {
    var s=step(state,key);
    if(!s.finished)s.tape=s.chain+(s.op&&s.entry?'':s.input);
    return s;
}
