import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
R="/home/user/hisab/"  # repo root; run from anywhere
S=2048  # supersample
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(len(a)))
def lin(w,h,stops,angle=45):
    a=math.radians(angle); dx,dy=math.cos(a),math.sin(a)
    img=Image.new('RGBA',(w,h)); px=img.load()
    L=abs(w*dx)+abs(h*dy)
    for y in range(h):
        for x in range(w):
            t=((x-w/2)*dx+(y-h/2)*dy)/L+.5
            t=min(max(t,0),1)
            for i in range(len(stops)-1):
                if stops[i][0]<=t<=stops[i+1][0]:
                    u=(t-stops[i][0])/(stops[i+1][0]-stops[i][0]); px[x,y]=lerp(stops[i][1],stops[i+1][1],u); break
    return img
def fill(mask,stops,angle):
    g=lin(mask.size[0],mask.size[1],stops,angle); g.putalpha(mask); return g

def build(S, with_bg=True):
    W=S
    out=Image.new('RGBA',(W,W),(0,0,0,0))
    if with_bg:
        bg=lin(W//4,W//4,[(0,(10,12,52,255)),(.55,(52,26,170,255)),(1,(124,63,242,255))],50).resize((W,W),Image.BICUBIC)
        # highlight
        hl=Image.new('RGBA',(W,W),(0,0,0,0)); d=ImageDraw.Draw(hl)
        d.ellipse([-W*.25,-W*.35,W*.75,W*.55],fill=(170,140,255,34)); hl=hl.filter(ImageFilter.GaussianBlur(W*.10))
        bg=Image.alpha_composite(bg,hl)
        # glow behind mark
        gl=Image.new('RGBA',(W,W),(0,0,0,0)); ImageDraw.Draw(gl).ellipse([W*.2,W*.2,W*.8,W*.8],fill=(140,110,255,120))
        bg=Image.alpha_composite(bg,gl.filter(ImageFilter.GaussianBlur(W*.12)))
        # subtle grid
        gr=Image.new('RGBA',(W,W),(0,0,0,0)); gd=ImageDraw.Draw(gr)
        for k in range(1,8):
            gd.line([(0,W*k/8),(W,W*k/8)],fill=(255,255,255,10),width=max(2,W//512))
            gd.line([(W*k/8,0),(W*k/8,W)],fill=(255,255,255,10),width=max(2,W//512))
        bg=Image.alpha_composite(bg,gr)
        m=Image.new('L',(W,W),0); ImageDraw.Draw(m).rounded_rectangle([0,0,W-1,W-1],radius=int(W*.225),fill=255)
        out.paste(bg,(0,0),m)
        # inner border shine
        bd=Image.new('RGBA',(W,W),(0,0,0,0)); ImageDraw.Draw(bd).rounded_rectangle([W*.006,W*.006,W*.994,W*.994],radius=int(W*.22),outline=(255,255,255,40),width=max(3,W//200))
        out=Image.alpha_composite(out,bd)
    # ---- the mark: H from two pillars + rising arrow crossbar
    cx=W/2; base=W*.76; pw=W*.13; gap=W*.20
    lx=cx-gap/2-pw; rx=cx+gap/2
    lt=W*.36; rt=W*.22  # tops: right pillar taller (growth)
    pill=Image.new('L',(W,W),0); pd=ImageDraw.Draw(pill)
    rad=int(pw*.32)
    pd.rounded_rectangle([lx,lt,lx+pw,base],radius=rad,fill=255)
    pd.rounded_rectangle([rx,rt,rx+pw,base],radius=rad,fill=255)
    # shadow
    sh=Image.new('RGBA',(W,W),(8,4,40,0)); sh.putalpha(pill.point(lambda v:int(v*.55)))
    sh=sh.filter(ImageFilter.GaussianBlur(W*.02)); sh=ImageChops.offset(sh,0,int(W*.018))
    out=Image.alpha_composite(out,sh)
    out=Image.alpha_composite(out,fill(pill,[(0,(255,255,255,255)),(1,(200,186,255,255))],90))
    # arrow crossbar: zig line rising from left pillar mid to above right pillar
    ar=Image.new('L',(W,W),0); ad=ImageDraw.Draw(ar)
    lw=int(W*.058)
    p0=(lx+pw*.45, W*.615); p1=(cx-W*.03, W*.535); p2=(cx+W*.035, W*.585)
    tip=(rx+pw*.62, W*.385)
    ang=math.atan2(tip[1]-p2[1],tip[0]-p2[0]); hs=W*.115
    base=(tip[0]-math.cos(ang)*hs, tip[1]-math.sin(ang)*hs)
    ad.line([p0,p1,p2,base],fill=255,width=lw,joint='curve')
    ad.ellipse([p0[0]-lw/2,p0[1]-lw/2,p0[0]+lw/2,p0[1]+lw/2],fill=255)
    for q in (p1,p2): ad.ellipse([q[0]-lw/2,q[1]-lw/2,q[0]+lw/2,q[1]+lw/2],fill=255)
    hw=hs*.62
    left=(base[0]+math.cos(ang+math.pi/2)*hw, base[1]+math.sin(ang+math.pi/2)*hw)
    right=(base[0]+math.cos(ang-math.pi/2)*hw, base[1]+math.sin(ang-math.pi/2)*hw)
    ad.polygon([tip,left,right],fill=255)
    # soft dark halo to lift the arrow off the pillars
    halo=Image.new('RGBA',(W,W),(20,10,90,0)); halo.putalpha(ar.filter(ImageFilter.GaussianBlur(W*.022)).point(lambda v:min(255,int(v*1.6))))
    out=Image.alpha_composite(out,halo)
    glow=fill(ar,[(0,(34,211,238,255)),(1,(52,211,153,255))],0).filter(ImageFilter.GaussianBlur(W*.03))
    out=Image.alpha_composite(out,glow)
    out=Image.alpha_composite(out,fill(ar,[(0,(56,189,248,255)),(1,(74,222,128,255))],-20))
    # AI sparkle near tip
    def star(c,r,col,blur=0):
        L=Image.new('L',(W,W),0); d=ImageDraw.Draw(L); pts=[]
        for k in range(8):
            a=math.pi/4*k-math.pi/2; rr=r if k%2==0 else r*.26
            pts.append((c[0]+rr*math.cos(a),c[1]+rr*math.sin(a)))
        d.polygon(pts,fill=255)
        st=Image.new('RGBA',(W,W),col); st.putalpha(L)
        return st
    sc=(tip[0]+W*.075,tip[1]-W*.135)
    gs=star(sc,W*.10,(255,210,90,255)).filter(ImageFilter.GaussianBlur(W*.025))
    out=Image.alpha_composite(out,gs)
    out=Image.alpha_composite(out,star(sc,W*.085,(255,224,138,255)))
    out=Image.alpha_composite(out,star((sc[0]+W*.02,sc[1]+W*.16),W*.032,(255,240,200,255)))
    return out

icon=build(S)
small=icon.resize((1024,1024),Image.LANCZOS)
small.save('pro_icon_1024.png')
for name,s in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    icon.resize((s,s),Image.LANCZOS).save(R+f'tool/android_res/mipmap-{name}/ic_launcher.png')
# in-app logo (512) with wordmark below mark area? keep pure icon for crisp UI
icon.resize((512,512),Image.LANCZOS).save(R+'assets/home/logo.png')
# wordmark (horizontal) for splash/login
W2=1600; H2=480
wm=Image.new('RGBA',(W2,H2),(0,0,0,0))
wm.paste(icon.resize((H2,H2),Image.LANCZOS),(0,0),icon.resize((H2,H2),Image.LANCZOS))
d=ImageDraw.Draw(wm)
f=ImageFont.truetype(R+'assets/pdf/Montserrat-Black.ttf',210)
d.text((H2+60,95),'Hisab',font=f,fill=(15,18,64,255))
bb=d.textbbox((H2+60,95),'Hisab',font=f)
ab=d.textbbox((bb[2]+40,95),'AI',font=f)
m=Image.new('L',(ab[2]-ab[0],ab[3]-ab[1]),0); ImageDraw.Draw(m).text((-(ab[0]-bb[2]-40),-(ab[1]-95)),'AI',font=f,fill=255)
g=fill(m,[(0,(124,63,242,255)),(1,(34,211,238,255))],0)
wm.alpha_composite(g,(ab[0],ab[1]))
wm.save('wordmark.png'); wm.save(R+'assets/home/wordmark.png')
