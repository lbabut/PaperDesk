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
function book() { return {version:1, index:0, nextCacheSlot:1, pages:[{strokes:[], paper:"plain",cacheSlot:0}]}; }
function point(x,y,p) {
    return [Math.round(clamp(x,0,WIDTH)*10)/10,Math.round(clamp(y,0,HEIGHT)*10)/10,
            Math.round(clamp(isFinite(p) && p>0 ? p : 0.5,0.04,1)*100)/100];
}
function stroke(tool,size,tone,strength,seed) {
    var t=tools[tool] || tools[1];
    return {renderer:7,tool:tool,size:clamp(size,1,80),tone:clamp(tone,0,238),
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
    var total=0,slots={},nextSlot=0;
    for(var i=0;i<b.pages.length;i++) {
        var page=b.pages[i];
        if(!page || ["plain","dots","grid"].indexOf(page.paper)<0 || !Array.isArray(page.strokes))
            throw Error("Invalid paper");
        var slot=page.cacheSlot===undefined?i:page.cacheSlot;
        if(!Number.isInteger(slot)||slot<0||slot>1000000000||slots[slot])throw Error("Invalid page identity");
        slots[slot]=true;page.cacheSlot=slot;nextSlot=Math.max(nextSlot,slot+1);
        for(var j=0;j<page.strokes.length;j++) {
            var s=page.strokes[j];
            if(!s || (s.renderer!==undefined && s.renderer!==2 && s.renderer!==3 && s.renderer!==4 && s.renderer!==5 && s.renderer!==6 && s.renderer!==7 && s.renderer!==8) || !Number.isInteger(s.tool) || s.tool<0 || s.tool>=tools.length ||
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
    b.nextCacheSlot=Number.isInteger(b.nextCacheSlot)&&b.nextCacheSlot>=nextSlot?b.nextCacheSlot:nextSlot;
    return b;
}
function noise(x,y,seed) {
    var n=Math.sin(x*12.9898+y*78.233+(seed%65536)*0.017)*43758.5453;
    return n-Math.floor(n);
}
function legacySmudge(c,a,b,size,strength) {
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
    if(s.renderer>=2) { fastSegment(c,s,index);return; }
    if(t.kind==="smudge") { legacySmudge(c,a,b,s.size,s.strength);return; }
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

function smudgeV2(c,a,b,size,strength) {
    var dx=b[0]-a[0],dy=b[1]-a[1],distance=Math.sqrt(dx*dx+dy*dy);
    if(distance<0.1) return;
    var radius=clamp(size/2,6,40),step=Math.max(3,radius*0.28);
    var steps=Math.max(1,Math.ceil(distance/step)),ox=a[0],oy=a[1];
    c.save();
    c.globalAlpha=clamp(strength*0.65,0.05,0.8);
    c.globalCompositeOperation="qt-darken";
    for(var i=1;i<=steps;i++) {
        var x=a[0]+dx*i/steps,y=a[1]+dy*i/steps;
        var sx=Math.max(0,Math.floor(ox-radius)),sy=Math.max(0,Math.floor(oy-radius));
        var w=Math.min(WIDTH-sx,Math.ceil(radius*2)),h=Math.min(HEIGHT-sy,Math.ceil(radius*2));
        if(w>0 && h>0) {
            var patch=c.getImageData(sx,sy,w,h);
            c.save();c.beginPath();c.arc(x,y,radius,0,Math.PI*2);c.clip();
            c.drawImage(patch,sx+x-ox,sy+y-oy);
            c.restore();
        }
        ox=x;oy=y;
    }
    c.restore();
}
function fastSegment(c,s,index) {
    var b=s.points[index],a=index?s.points[index-1]:b,t=tools[s.tool];
    if(t.kind==="smudge") {
        if(s.renderer===2)smudgeV2(c,a,b,s.size,s.strength);
        else if(s.renderer===3)smudgeV3(c,a,b,s.size,s.strength);
        else if(s.renderer===4)smudgeV4(c,a,b,s.size,s.strength);
        else if(s.renderer===5)smudgeV5(c,a,b,s.size,s.strength);
        else smudge(c,a,b,s.size,s.strength*(s.renderer>=7?(a[2]+b[2])/2:1));
        return;
    }
    var p=(a[2]+b[2])*0.5,w=Math.max(0.8,s.size*(0.18+0.82*p));
    var value=t.kind==="eraser"?255:s.tone;
    var alpha=t.kind==="eraser"?s.strength:t.opacity*s.strength*(0.3+0.7*p);
    c.save();c.lineCap="round";c.lineJoin="round";
    if(!index || (a[0]===b[0] && a[1]===b[1])) {
        c.fillStyle="rgba("+value+","+value+","+value+","+alpha+")";
        c.beginPath();c.arc(b[0],b[1],w/2,0,Math.PI*2);c.fill();
    } else {
        var layers=t.kind==="charcoal"?3:1;
        for(var i=0;i<layers;i++) {
            c.lineWidth=w*(1-i*0.22);
            c.strokeStyle="rgba("+value+","+value+","+value+","+(alpha*(layers===1?1:[0.3,0.6,0.5][i]))+")";
            c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();
        }
        if(t.kind==="pencil" && w>3) {
            c.lineWidth=Math.max(0.5,w*0.06);
            c.strokeStyle="rgba("+value+","+value+","+value+","+alpha*t.grain+")";
            var offset=s.renderer>=6?(noise(0,0,s.seed)-0.5)*w*0.15:(noise(a[0],a[1],s.seed)-0.5)*w*0.6;
            c.beginPath();c.moveTo(a[0]+offset,a[1]);c.lineTo(b[0]+offset,b[1]);c.stroke();
        }
    }
    c.restore();
}
function dirtyBounds(s,index) {
    var b=s.points[index],a=index?s.points[index-1]:b,r=s.size+4;
    return {x:Math.max(0,Math.min(a[0],b[0])-r),y:Math.max(0,Math.min(a[1],b[1])-r),
            width:Math.abs(b[0]-a[0])+r*2,height:Math.abs(b[1]-a[1])+r*2};
}

function smudgeV3(c,a,b,size,strength) {
    var dx=b[0]-a[0],dy=b[1]-a[1],distance=Math.sqrt(dx*dx+dy*dy);
    if(distance<0.1) return;
    var radius=clamp(size/2,6,40),step=Math.max(4,radius*0.4);
    var sx=Math.max(0,Math.floor(Math.min(a[0],b[0])-radius));
    var sy=Math.max(0,Math.floor(Math.min(a[1],b[1])-radius));
    var w=Math.min(WIDTH-sx,Math.ceil(Math.abs(dx)+radius*2));
    var h=Math.min(HEIGHT-sy,Math.ceil(Math.abs(dy)+radius*2));
    if(w<=0 || h<=0)return;
    var patch=c.getImageData(sx,sy,w,h);
    var shift=Math.min(distance,radius*0.75),tx=dx/distance*shift,ty=dy/distance*shift;
    var steps=Math.max(1,Math.ceil(distance/step));
    c.save();c.globalAlpha=clamp(strength*0.65,0.05,0.8);c.globalCompositeOperation="qt-darken";
    for(var i=0;i<=steps;i++) {
        var x=a[0]+dx*i/steps,y=a[1]+dy*i/steps;
        c.save();c.beginPath();c.arc(x,y,radius,0,Math.PI*2);c.clip();
        c.drawImage(patch,sx+tx,sy+ty);c.restore();
    }
    c.restore();
}

function previewSegment(c,s,index) {
    if(s.tool===7)return;
    var b=s.points[index],a=index?s.points[index-1]:b,p=(a[2]+b[2])/2,t=tools[s.tool];
    var w=Math.max(1,s.size*(0.18+0.82*p));
    var alpha=t.kind==="eraser"?s.strength:t.opacity*s.strength*(0.3+0.7*p);
    var value=t.kind==="eraser"?255:s.tone,gray=Math.round(255-(255-value)*Math.max(0.35,alpha));
    c.save();c.strokeStyle=Qt.rgba(gray/255,gray/255,gray/255,1);
    c.fillStyle=c.strokeStyle;c.lineWidth=w;c.lineCap="round";c.lineJoin="round";
    if(!index) {c.beginPath();c.arc(b[0],b[1],w/2,0,Math.PI*2);c.fill();}
    else {c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();}
    c.restore();
}

function smudgeV4(c,a,b,size,strength) {blendSmudge(c,a,b,size,strength,false);}
function smudgeV5(c,a,b,size,strength) {blendSmudge(c,a,b,size,strength,true);}
function blendSmudge(c,a,b,size,strength,directional) {
    var dx=b[0]-a[0],dy=b[1]-a[1],distance=Math.sqrt(dx*dx+dy*dy);
    if(distance<0.1)return;
    var r=clamp(size/2,6,40),pad=r*2;
    var sx=Math.max(0,Math.floor(Math.min(a[0],b[0])-pad));
    var sy=Math.max(0,Math.floor(Math.min(a[1],b[1])-pad));
    var w=Math.min(WIDTH-sx,Math.ceil(Math.abs(dx)+pad*2));
    var h=Math.min(HEIGHT-sy,Math.ceil(Math.abs(dy)+pad*2));
    if(w<=0 || h<=0)return;
    var patch=c.getImageData(sx,sy,w,h),ux=dx/distance,uy=dy/distance,shift=r*0.95;
    var offsets=directional?[[0,0,0.3],[ux*shift,uy*shift,0.5],[-ux*shift,-uy*shift,0.05],
                 [-uy*shift,ux*shift,0.075],[uy*shift,-ux*shift,0.075]]:[[0,0,0.45],[ux*shift,uy*shift,0.2],[-ux*shift,-uy*shift,0.1],
                 [-uy*shift,ux*shift,0.125],[uy*shift,-ux*shift,0.125]];
    var angle=Math.atan2(dy,dx);
    c.save();c.globalCompositeOperation="source-over";
    for(var ring=0;ring<3;ring++) {
        var radius=r*(1-ring*0.25),mix=clamp(strength,0.05,1)*(directional?[0.2,0.4,0.65]:[0.18,0.28,0.38])[ring];
        c.save();c.beginPath();
        c.moveTo(a[0]-uy*radius,a[1]+ux*radius);
        c.lineTo(b[0]-uy*radius,b[1]+ux*radius);
        c.arc(b[0],b[1],radius,angle+Math.PI/2,angle-Math.PI/2,true);
        c.lineTo(a[0]+uy*radius,a[1]-ux*radius);
        c.arc(a[0],a[1],radius,angle-Math.PI/2,angle+Math.PI/2,true);
        c.closePath();c.clip();
        var cumulative=1-mix;
        for(var i=0;i<offsets.length;i++) {
            var o=offsets[i],weight=mix*o[2];cumulative+=weight;
            c.globalAlpha=weight/cumulative;
            c.drawImage(patch,sx+o[0],sy+o[1]);
        }
        c.restore();
    }
    c.restore();
}
function smudge(c,a,b,size,strength) {
    var dx=b[0]-a[0],dy=b[1]-a[1],len2=dx*dx+dy*dy;
    if(len2<0.01)return;
    var distance=Math.sqrt(len2),r=clamp(size/2,6,40),pad=Math.ceil(r*2);
    var sx=Math.max(0,Math.floor(Math.min(a[0],b[0])-pad));
    var sy=Math.max(0,Math.floor(Math.min(a[1],b[1])-pad));
    var w=Math.min(WIDTH-sx,Math.ceil(Math.abs(dx)+pad*2)),h=Math.min(HEIGHT-sy,Math.ceil(Math.abs(dy)+pad*2));
    if(w<=0 || h<=0)return;
    var image=c.getImageData(sx,sy,w,h),data=image.data,n=w*h;
    var gray=new Float32Array(n),horizontal=new Float32Array(n),blur=new Float32Array(n);
    for(var i=0;i<n;i++)gray[i]=data[i*4];
    var br=Math.max(1,Math.round(r*0.18)),diameter=br*2+1;
    for(var y=0;y<h;y++) {
        var row=y*w,sum=0;
        for(var k=-br;k<=br;k++)sum+=gray[row+clamp(k,0,w-1)];
        for(var x=0;x<w;x++) {
            horizontal[row+x]=sum/diameter;
            sum+=gray[row+Math.min(w-1,x+br+1)]-gray[row+Math.max(0,x-br)];
        }
    }
    for(var x=0;x<w;x++) {
        var sum=0;
        for(var k=-br;k<=br;k++)sum+=horizontal[clamp(k,0,h-1)*w+x];
        for(var y=0;y<h;y++) {
            blur[y*w+x]=sum/diameter;
            sum+=horizontal[Math.min(h-1,y+br+1)*w+x]-horizontal[Math.max(0,y-br)*w+x];
        }
    }
    var ux=dx/distance,uy=dy/distance,shift=Math.min(distance,r*0.8),radius2=r*r;
    var opacity=clamp(strength,0.05,1)*0.65;
    for(var y=0;y<h;y++)for(var x=0;x<w;x++) {
        var px=sx+x-a[0],py=sy+y-a[1],t=clamp((px*dx+py*dy)/len2,0,1);
        var ex=px-t*dx,ey=py-t*dy,falloff=1-(ex*ex+ey*ey)/radius2;
        if(falloff<=0)continue;
        falloff=falloff*falloff;
        var fx=clamp(x-ux*shift*falloff,0,w-1),fy=clamp(y-uy*shift*falloff,0,h-1);
        var ix=Math.floor(fx),iy=Math.floor(fy),jx=Math.min(w-1,ix+1),jy=Math.min(h-1,iy+1);
        var mx=fx-ix,my=fy-iy;
        var transported=(blur[iy*w+ix]*(1-mx)+blur[iy*w+jx]*mx)*(1-my)
                       +(blur[jy*w+ix]*(1-mx)+blur[jy*w+jx]*mx)*my;
        var at=y*w+x,mix=opacity*falloff,value=Math.round(gray[at]*(1-mix)+transported*mix);
        data[at*4]=value;data[at*4+1]=value;data[at*4+2]=value;data[at*4+3]=255;
    }
    c.putImageData(image,sx,sy,0,0,w,h);
}
