var WIDTH = 1200, HEIGHT = 1600, MAX_POINTS = 64000;
var tools = [
    {name:"2H", kind:"pencil", size:3, opacity:0.22, grain:0.35},
    {name:"HB", kind:"pencil", size:5, opacity:0.38, grain:0.3},
    {name:"2B", kind:"pencil", size:8, opacity:0.53, grain:0.24},
    {name:"6B", kind:"pencil", size:12, opacity:0.7, grain:0.18},
    {name:"Charcoal", kind:"charcoal", size:24, opacity:0.5, grain:0.65},
    {name:"Soft coal", kind:"charcoal", size:38, opacity:0.35, grain:0.8},
    {name:"Eraser", kind:"eraser", size:30, opacity:1, grain:0},
    {name:"Smudge", kind:"smudge", size:40, opacity:0.6, grain:0}
];
function clamp(n,a,b) { return Math.max(a, Math.min(b,n)); }
function book() { return {version:1, index:0, pages:[{strokes:[], paper:"plain"}]}; }
function point(x,y,p) {
    return [Math.round(clamp(x,0,WIDTH)*10)/10,Math.round(clamp(y,0,HEIGHT)*10)/10,
            Math.round(clamp(isFinite(p) && p>0 ? p : 0.5,0.04,1)*100)/100];
}
function stroke(tool,size,tone,strength,seed) {
    var t=tools[tool] || tools[1];
    return {tool:tool,size:clamp(size,1,80),tone:clamp(tone,0,238),
            strength:clamp(strength,0.05,1),seed:seed>>>0,points:[]};
}
function count(b) {
    var n=0;
    for(var i=0;i<b.pages.length;i++)
        for(var j=0;j<b.pages[i].strokes.length;j++) n+=b.pages[i].strokes[j].points.length;
    return n;
}
function decode(raw) {
    var b=JSON.parse(raw);
    if(!b || b.version!==1 || !Array.isArray(b.pages) || !b.pages.length || b.pages.length>12)
        throw Error("Invalid sketchbook");
    if(!Number.isInteger(b.index) || b.index<0 || b.index>=b.pages.length) throw Error("Invalid page");
    var total=0;
    for(var i=0;i<b.pages.length;i++) {
        var page=b.pages[i];
        if(!page || ["plain","dots","grid"].indexOf(page.paper)<0 || !Array.isArray(page.strokes))
            throw Error("Invalid paper");
        for(var j=0;j<page.strokes.length;j++) {
            var s=page.strokes[j];
            if(!s || !Number.isInteger(s.tool) || s.tool<0 || s.tool>=tools.length ||
               !isFinite(s.size) || s.size<1 || s.size>80 || !isFinite(s.tone) || s.tone<0 || s.tone>238 ||
               !isFinite(s.strength) || s.strength<0.05 || s.strength>1 || !isFinite(s.seed) ||
               !Array.isArray(s.points) || !s.points.length) throw Error("Invalid stroke");
            total+=s.points.length;
            if(total>MAX_POINTS) throw Error("Sketchbook is full");
            for(var k=0;k<s.points.length;k++) {
                var p=s.points[k];
                if(!Array.isArray(p) || p.length!==3 || !p.every(function(v){return typeof v==="number" && isFinite(v);}) ||
                   p[0]<0 || p[0]>WIDTH || p[1]<0 || p[1]>HEIGHT || p[2]<0.04 || p[2]>1)
                    throw Error("Invalid point");
            }
        }
    }
    return b;
}
function noise(x,y,seed) {
    var n=Math.sin(x*12.9898+y*78.233+(seed%65536)*0.017)*43758.5453;
    return n-Math.floor(n);
}
function smudge(c,a,b,size,strength) {
    var dx=clamp(b[0]-a[0],-12,12), dy=clamp(b[1]-a[1],-12,12);
    if(Math.abs(dx)+Math.abs(dy)<0.1) return;
    var r=Math.max(3,Math.min(32,size/2)), pad=14;
    var x=Math.max(0,Math.floor(b[0]-r-pad)),y=Math.max(0,Math.floor(b[1]-r-pad));
    var w=Math.min(WIDTH-x,Math.ceil(2*(r+pad))),h=Math.min(HEIGHT-y,Math.ceil(2*(r+pad)));
    if(w<1 || h<1) return;
    var image=c.getImageData(x,y,w,h), d=image.data, source=[];
    for(var k=0;k<d.length;k+=4) source[k/4]=d[k];
    for(var py=0;py<h;py++) for(var px=0;px<w;px++) {
        var ox=x+px-b[0],oy=y+py-b[1],distance=Math.sqrt(ox*ox+oy*oy)/r;
        if(distance>=1) continue;
        var sx=clamp(Math.round(px-dx),0,w-1),sy=clamp(Math.round(py-dy),0,h-1);
        var at=(py*w+px)*4, from=source[sy*w+sx],mix=(1-distance*distance)*strength*0.72;
        var v=Math.round(d[at]*(1-mix)+from*mix);
        d[at]=v;d[at+1]=v;d[at+2]=v;d[at+3]=255;
    }
    c.putImageData(image,x,y,0,0,w,h);
}
function segment(c,s,index) {
    var b=s.points[index],a=index?s.points[index-1]:b,t=tools[s.tool];
    if(t.kind==="smudge") { smudge(c,a,b,s.size,s.strength);return; }
    var dx=b[0]-a[0],dy=b[1]-a[1],dist=Math.sqrt(dx*dx+dy*dy);
    var steps=Math.max(1,Math.ceil(dist/Math.max(0.8,s.size*0.17)));
    c.save();
    for(var i=1;i<=steps;i++) {
        var f=i/steps,x=a[0]+dx*f,y=a[1]+dy*f,p=a[2]+(b[2]-a[2])*f;
        var radius=s.size*(0.18+0.82*p)/2;
        if(t.kind==="eraser") {
            c.fillStyle="rgba(255,255,255,"+s.strength+")";
            c.beginPath();c.arc(x,y,Math.max(2,radius),0,Math.PI*2);c.fill();
        } else {
            var grain=t.grain,alpha=t.opacity*s.strength*(0.22+0.78*p);
            c.fillStyle="rgba("+s.tone+","+s.tone+","+s.tone+","+alpha*0.42+")";
            c.beginPath();c.arc(x,y,Math.max(0.5,radius),0,Math.PI*2);c.fill();
            var flecks=t.kind==="charcoal"?10:4;
            for(var n=0;n<flecks;n++) {
                var u=noise(x+n,y,s.seed),v=noise(y+n,x,s.seed+19);
                var gx=x+(u*2-1)*radius,gy=y+(v*2-1)*radius;
                if((gx-x)*(gx-x)+(gy-y)*(gy-y)>radius*radius) continue;
                c.fillStyle="rgba("+s.tone+","+s.tone+","+s.tone+","+alpha*(1-grain*noise(gx,gy,s.seed))+")";
                c.fillRect(gx,gy,t.kind==="charcoal"?1.7:0.85,t.kind==="charcoal"?1.7:0.85);
            }
        }
    }
    c.restore();
}
function background(c,paper) {
    c.fillStyle="white";c.fillRect(0,0,WIDTH,HEIGHT);
}
function guides(c,paper) {
    c.save();c.fillStyle="#bbbbbb";c.strokeStyle="#dddddd";c.lineWidth=0.8;
    if(paper==="dots") {
        for(var y=24;y<HEIGHT;y+=32) for(var x=24;x<WIDTH;x+=32) c.fillRect(x,y,1.5,1.5);
    } else if(paper==="grid") {
        c.beginPath();
        for(var gx=24;gx<WIDTH;gx+=32){c.moveTo(gx,0);c.lineTo(gx,HEIGHT);}
        for(var gy=24;gy<HEIGHT;gy+=32){c.moveTo(0,gy);c.lineTo(WIDTH,gy);}
        c.stroke();
    }
    c.restore();
}
