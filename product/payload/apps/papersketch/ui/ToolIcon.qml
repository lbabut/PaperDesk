import QtQuick 2.15

// Small vector glyphs use the existing Canvas backend, so the toolbar does not
// depend on a tablet image-format plugin or a font with special icon glyphs.
Canvas {
    id:icon
    property string iconName:""
    property bool inverted:false
    antialiasing:true
    onIconNameChanged:requestPaint()
    onInvertedChanged:requestPaint()
    onWidthChanged:requestPaint()
    onHeightChanged:requestPaint()
    onAvailableChanged:if(available)requestPaint()

    function path(c,data,fill,color,lineWidth) {
        c.beginPath();var x=0,y=0;
        var commands=data.match(/[MLHVQCZ][^MLHVQCZ]*/g) || [];
        for(var i=0;i<commands.length;i++) {
            var command=commands[i][0],values=commands[i].substring(1).match(/-?\d*\.?\d+/g) || [];
            var v=values.map(Number);
            if(command==="M"){x=v[0];y=v[1];c.moveTo(x,y);}
            else if(command==="L"){x=v[0];y=v[1];c.lineTo(x,y);}
            else if(command==="H"){x=v[0];c.lineTo(x,y);}
            else if(command==="V"){y=v[0];c.lineTo(x,y);}
            else if(command==="Q"){c.quadraticCurveTo(v[0],v[1],v[2],v[3]);x=v[2];y=v[3];}
            else if(command==="C"){c.bezierCurveTo(v[0],v[1],v[2],v[3],v[4],v[5]);x=v[4];y=v[5];}
            else c.closePath();
        }
        if(fill){c.fillStyle=fill;c.fill();}
        c.strokeStyle=color;c.lineWidth=lineWidth || 2.2;c.stroke();
    }
    onPaint:{
        var c=getContext("2d"),fg=inverted?"white":"black",bg=inverted?"black":"white";
        c.reset();c.scale(width/56,height/50);c.lineCap="round";c.lineJoin="round";
        if(iconName.indexOf("pencil-")===0) {
            path(c,"M9 7 Q9 4 12 4 H22 Q25 4 25 7 V35 L17 47 L9 35 Z",bg,fg);
            path(c,"M9 11 H25 M9 35 H25 M14 12 V33 M20 12 V33 M13 42 L17 47 L21 42 Z",null,fg);
            var grades={"pencil-2h":"2H","pencil-hb":"HB","pencil-2b":"2B","pencil-6b":"6B"};
            var glyphs={
                "2":"M0 2 C0 -1 6 -1 6 2 C6 4 0 5 0 8 H6",
                "H":"M0 0 V8 M6 0 V8 M0 4 H6",
                "B":"M0 0 V8 H3 C7 8 7 4 3 4 H0 M0 0 H3 C7 0 7 4 3 4",
                "6":"M6 1 C0 -2 -1 6 2 8 C8 11 9 1 2 4 H0"
            },grade=grades[iconName];
            for(var i=0;i<grade.length;i++) {
                c.save();c.translate(31+i*11,12);c.scale(1.25,1.25);
                path(c,glyphs[grade[i]],null,fg,1.6);c.restore();
            }
            path(c,"M33 36 L51 32 M33 41 L51 37",null,fg,["2H","HB","2B","6B"].indexOf(grade)+1);
        } else if(iconName==="charcoal") {
            path(c,"M14 6 L29 4 L35 10 L27 44 L12 47 L7 41 Z",fg,fg);
            path(c,"M16 11 L13 31 M23 8 L18 35 M27 15 L23 29",null,bg);
            path(c,"M36 35 L51 30 M34 42 L50 37",null,fg,3);
        } else if(iconName==="soft-charcoal") {
            path(c,"M10 7 L29 4 L38 12 L30 43 L17 47 L6 40 Z",fg,fg);
            path(c,"M15 11 L12 28 M24 8 L19 22 M30 16 L26 33 M11 35 L18 39",null,bg);
            path(c,"M40 33 L51 29 M37 40 L51 35 M35 46 L50 41",null,fg,4);
            path(c,"M6 46 H7 M37 8 H38 M45 47 H46",null,fg,2);
        } else if(iconName==="rapidograph") {
            path(c,"M18 4 H33 V29 L29 36 H22 L18 29 Z",bg,fg);
            path(c,"M18 12 H33 M18 17 H33 M22 29 H29 M24 36 V45 M27 36 V45 M23 46 H28",null,fg);
            path(c,"M38 34 H52 M38 41 H52",null,fg,1.5);
        } else if(iconName==="eraser") {
            path(c,"M6 30 L27 7 Q29 5 32 7 L49 22 Q51 24 49 27 L33 45 H21 Z",bg,fg);
            path(c,"M17 18 L40 37 M6 30 L21 45 H33 L40 37 L17 18 Z",fg,fg);
            path(c,"M30 46 H52",null,fg);
        } else if(iconName==="materials") {
            path(c,"M8 7 H43 V43 H8 Z",bg,fg);
            path(c,"M14 14 H26 M14 20 H24 M14 27 H21 M14 34 H19",null,fg);
            path(c,"M28 35 L38 13 L45 16 L35 38 L29 42 Z",bg,fg);
            path(c,"M29 35 L35 38 M28 40 L29 42 L33 40 Z",fg,fg);
            path(c,"M18 13 H19 M22 33 H23 M19 39 H20",null,fg,2);
        } else if(iconName==="smudge") {
            path(c,"M22 42 C15 36 11 31 12 28 Q13 24 17 27 L22 32 V9 Q22 3 27 4 Q31 4 31 10 V23 Q32 20 35 21 Q38 22 38 26 Q39 23 42 25 Q45 26 44 30 Q47 28 49 32 L48 39 Q47 46 39 47 H29 Z",bg,fg);
            path(c,"M31 23 V31 M38 26 V32 M44 30 V34 M5 43 Q9 39 14 43 M4 48 Q10 44 16 48",null,fg);
            path(c,"M8 37 H10",null,fg,3);
        }
    }
}
