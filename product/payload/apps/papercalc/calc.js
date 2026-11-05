// Bounded real-valued scientific parser. Never evaluates JavaScript.
function calculate(source, options) {
    try {
        options = options || {};
        var degrees = options.angleMode !== 'RAD';
        if (typeof source !== 'string' || source.length > 160) throw Error("Expression is too long");
        var text = source.replace(/,/g, '.').replace(/×/g, '*').replace(/[÷:]/g, '/').replace(/−/g, '-').replace(/π/g, 'pi').replace(/√/g, 'sqrt');
        var pos = 0, depth = 0;
        function enter() { if (++depth > 32) throw Error("Expression is too complex"); }
        function space() { while (pos < text.length && /\s/.test(text.charAt(pos))) pos++; }
        function checked(n) { if (!isFinite(n)) throw Error("Result is outside the real-number range"); return n; }
        function fn(name, n) {
            var a, reduced;
            if (name === 'sin' || name === 'cos' || name === 'tan') {
                reduced = degrees ? n % 360 : n % (2*Math.PI);
                a = degrees ? reduced*Math.PI/180 : reduced;
                if (name === 'tan' && Math.abs(Math.cos(a)) < 1e-15) throw Error("Tangent is undefined at this angle");
                if (name === 'sin') return reduced === 0 || Math.abs(reduced) === (degrees?180:Math.PI) ? 0 : Math.sin(a);
                if (name === 'cos') return Math.abs(reduced) === (degrees?90:Math.PI/2) || Math.abs(reduced) === (degrees?270:3*Math.PI/2) ? 0 : Math.cos(a);
                return Math.tan(a);
            }
            if (name === 'asin' || name === 'acos') {
                if (n < -1 || n > 1) throw Error("Argument of "+name+" must be between −1 and 1");
                a = name === 'asin' ? Math.asin(n) : Math.acos(n);
                return degrees ? a*180/Math.PI : a;
            }
            if (name === 'atan') { a=Math.atan(n);return degrees?a*180/Math.PI:a; }
            if (name === 'sqrt') { if(n<0)throw Error("Square root requires a number ≥ 0");return Math.sqrt(n); }
            if (name === 'ln' || name === 'log') { if(n<=0)throw Error("Logarithm requires a number > 0");return name==='ln'?Math.log(n):Math.log(n)/Math.LN10; }
            if (name === 'abs') return Math.abs(n);
            if (name === 'exp') return checked(Math.exp(n));
            throw Error("Unknown function: "+name);
        }
        function atom() {
            enter();space();var c=text.charAt(pos), n;
            if (c === '(') { pos++;n=sum();space();if(text.charAt(pos++)!==')')throw Error("Missing closing parenthesis )"); }
            else if (/[a-z]/i.test(c) && c) {
                var name=/^[a-z]+/i.exec(text.slice(pos))[0].toLowerCase();pos+=name.length;
                if (name==='pi') n=Math.PI;
                else if (name==='e') n=Math.E;
                else if (name==='x' && options.x!==undefined) n=checked(Number(options.x));
                else if (name==='ans') n=checked(options.ans===undefined?0:Number(options.ans));
                else {
                    space();if(text.charAt(pos++)!=='(')throw Error("Function "+name+" requires parentheses");
                    n=sum();space();if(text.charAt(pos++)!==')')throw Error("Missing closing parenthesis )");n=checked(fn(name,n));
                }
            } else {
                var m=/^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/.exec(text.slice(pos));
                if(!m)throw Error("Expected a number or function");
                pos+=m[0].length;n=checked(Number(m[0]));
            }
            depth--;return n;
        }
        function postfix() {
            var n=atom();space();
            while(text.charAt(pos)==='!') {
                pos++;if(n<0 || Math.floor(n)!==n)throw Error("Factorial requires a nonnegative integer");
                if(n>170)throw Error("Factorial supports numbers up to 170");
                var value=1;for(var i=2;i<=n;i++)value*=i;n=checked(value);space();
            }return n;
        }
        function power() {
            var n=postfix();space();
            if(text.charAt(pos)==='^'){pos++;n=checked(Math.pow(n,signed()));}return n;
        }
        function signed() {
            enter();space();var c=text.charAt(pos),n;
            if(c==='+' || c==='-'){pos++;n=signed();if(c==='-')n=-n;}
            else n=power();depth--;return n;
        }
        function product() {
            var n=signed();space();
            while(text.charAt(pos)==='*' || text.charAt(pos)==='/') {
                var op=text.charAt(pos++),rhs=signed();
                if(op==='/' && rhs===0)throw Error("Cannot divide by zero");
                n=checked(op==='*'?n*rhs:n/rhs);space();
            }return n;
        }
        function sum() {
            var n=product();space();
            while(text.charAt(pos)==='+' || text.charAt(pos)==='-') {
                var op=text.charAt(pos++),rhs=product();n=checked(op==='+'?n+rhs:n-rhs);space();
            }return n;
        }
        if(!text.trim())throw Error("Enter an expression");
        var result=sum();space();
        if(pos!==text.length)throw Error("Check the symbol at position "+(pos+1));
        return {ok:true,value:result,text:String(Number(result.toPrecision(12)))};
    } catch(e) { return {ok:false,text:e.message}; }
}

// Event-driven bounded sampling: a domain hole always breaks the polyline.
function sample(source, xmin, xmax, count, angle) {
    count=Math.max(2,Math.min(601,Math.floor(count)));
    var points=[];
    for(var i=0;i<count;i++) {
        var x=xmin+(xmax-xmin)*i/(count-1),r=calculate(source,{x:x,angleMode:angle||'RAD'});
        points.push({x:x,y:r.ok?r.value:null});
    }
    return points;
}
function rootBetween(source,a,b,angle) {
    var fa=calculate(source,{x:a,angleMode:angle}),fb=calculate(source,{x:b,angleMode:angle});
    if(!fa.ok||!fb.ok||fa.value*fb.value>0)return null;
    if(fa.value===0)return a;if(fb.value===0)return b;
    var m,r;
    for(var i=0;i<60;i++) {
        m=(a+b)/2;r=calculate(source,{x:m,angleMode:angle});if(!r.ok)return null;
        if(Math.abs(r.value)<1e-10)return m;
        if(fa.value*r.value<=0)b=m;else{a=m;fa=r;}
    }
    // Reject poles; a sign change alone does not establish a root.
    return r && Math.abs(r.value)<1e-7?m:null;
}
