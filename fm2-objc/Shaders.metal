#include <metal_stdlib>
using namespace metal;

constant uint height = 3000;
constant uint width = 3000;
constant float g = (sqrt(5.0f)+1)/2;

inline float random(thread float *seed) {
    *seed = fract(*seed + 1/g);
    return *seed;
}

kernel void gradient(
                     device float3  *out,
                     uint2 id [[ thread_position_in_grid ]]) {
                         uint row = id.x;
                         uint col = id.y;
                         uint index = row*3000 + col;
                         out[index].r = 1.0*row/height;
                         out[index].b = 1.0*col/width;
                         out[index].g = 1.0*row/height*col/width;
                     }

struct Ray { float3 o, d; Ray(float3 o_, float3 d_) : o(o_), d(d_) {} };
enum Refl_t { DIFF, SPEC, REFR };  // material types, used in radiance()
struct Sphere {
  float rad;       // radius
  float3 p, e, c;      // position, emission, color
  Refl_t refl;      // reflection type (DIFFuse, SPECular, REFRactive)
  Sphere(float rad_, float3 p_, float3 e_, float3 c_, Refl_t refl_):
    rad(rad_), p(p_), e(e_), c(c_), refl(refl_) {}
  float intersect(thread const Ray &r) const { // returns distance, 0 if nohit
    float3 op = p-r.o; // Solve t^2*d.d + 2*t*(o-p).d + (o-p).(o-p)-R^2 = 0
    float t, eps=1e-4, b=dot(op,r.d), det=b*b-dot(op,op)+rad*rad;
    if (det<0) return 0; else det=sqrt(det);
    return (t=b-det)>eps ? t : ((t=b+det)>eps ? t : 0);
  }
};
constant Sphere spheres[] = {//Scene: radius, position, emission, color, material
  Sphere(1e5, float3( 1e5+1,40.8,81.6), float3(),float3(.75,.25,.25),DIFF),//Left
  Sphere(1e5, float3(-1e5+99,40.8,81.6),float3(),float3(.25,.25,.75),DIFF),//Rght
  Sphere(1e5, float3(50,40.8, 1e5),     float3(),float3(.75,.75,.75),DIFF),//Back
  Sphere(1e5, float3(50,40.8,-1e5+170), float3(),float3(),           DIFF),//Frnt
  Sphere(1e5, float3(50, 1e5, 81.6),    float3(),float3(.75,.75,.75),DIFF),//Botm
  Sphere(1e5, float3(50,-1e5+81.6,81.6),float3(),float3(.75,.75,.75),DIFF),//Top
  Sphere(16.5,float3(27,16.5,47),       float3(),float3(1,1,1)*.999, SPEC),//Mirr
  Sphere(16.5,float3(73,16.5,78),       float3(),float3(1,1,1)*.999, REFR),//Glas
  Sphere(1.5, float3(50,81.6-16.5,81.6),float3(4,4,4)*100,  float3(), DIFF),//Lite
};
constant int numSpheres = sizeof(spheres)/sizeof(Sphere);
inline float clamp(float x){ return x<0 ? 0 : x>1 ? 1 : x; }
inline int toInt(float x){ return int(pow(clamp(x),1/2.2)*255+.5); }
inline bool intersect(thread const Ray &r, thread float &t, thread int &id){
  float n=sizeof(spheres)/sizeof(Sphere), d, inf=t=1e20;
  for(int i=int(n);i--;) if((d=spheres[i].intersect(r))&&d<t){t=d;id=i;}
  return t<inf;
}
float3 radiance(thread const Ray &r, int depth, thread float *Xi,int E=1){
  float t;                               // distance to intersection
  int id=0;                               // id of intersected object
  if (!intersect(r, t, id)) return float3(); // if miss, return black
  thread const Sphere &obj = spheres[id];        // the hit object
  float3 x=r.o+r.d*t, n=(x-obj.p).norm(), nl=dot(n,r.d)<0?n:n*-1, f=obj.c;
  float p = f.x>f.y && f.x>f.z ? f.x : f.y>f.z ? f.y : f.z; // max refl
  if (++depth>5||!p) if (random(Xi)<p) f=f*(1/p); else return obj.e*E;
  if (obj.refl == DIFF){                  // Ideal DIFFUSE reflection
    float r1=2*M_PI_F*random(Xi), r2=random(Xi), r2s=sqrt(r2);
    float3 w=nl, u=((fabs(w.x)>.1?float3(0,1,0):cross(float3(1,0,0),w)).norm(), v=cross(w,u);
    float3 d = normalize(u*cos(r1)*r2s + v*sin(r1)*r2s + w*sqrt(1-r2));

    // Loop over any lights
    float3 e;
    for (int i=0; i<numSpheres; i++){
      thread const Sphere &s = spheres[i];
      if (s.e.x<=0 && s.e.y<=0 && s.e.z<=0) continue; // skip non-lights
      
      float3 sw=s.p-x, su=((fabs(sw.x)>.1?float3(0,1,0):cross(float3(1,0,0),sw)).norm(), sv=cross(sw,su);
      float cos_a_max = sqrt(1-s.rad*s.rad/(x-s.p).dot(x-s.p));
      float eps1 = random(Xi), eps2 = random(Xi);
      float cos_a = 1-eps1+eps1*cos_a_max;
      float sin_a = sqrt(1-cos_a*cos_a);
      float phi = 2*M_PI_F*eps2;
      float3 l = normalize(su*cos(phi)*sin_a + sv*sin(phi)*sin_a + sw*cos_a);
      if (intersect(Ray(x,l), t, id) && id==i){  // shadow ray
        float omega = 2*M_PI_F*(1-cos_a_max);
        e = e + f*(s.e*dot(l,nl)*omega)*M_1_PI_F;  // 1/pi for brdf
      }
    }
    
    return obj.e*E+e+f*radiance(Ray(x,d),depth,Xi,0);
  } else if (obj.refl == SPEC)              // Ideal SPECULAR reflection
    return obj.e + f*radiance(Ray(x,r.d-n*2*dot(n,r.d)),depth,Xi);
  Ray reflRay(x, r.d-n*2*dot(n,r.d));     // Ideal dielectric REFRACTION
  bool into = dot(n,nl)>0;                // Ray from outside going in?
  float nc=1, nt=1.5, nnt=into?nc/nt:nt/nc, ddn=dot(r.d,nl), cos2t;
  if ((cos2t=1-nnt*nnt*(1-ddn*ddn))<0)    // Total internal reflection
    return obj.e + f*radiance(reflRay,depth,Xi);
  float3 tdir = normalize(r.d*nnt - n*((into?1:-1)*(ddn*nnt+sqrt(cos2t))));
  float a=nt-nc, b=nt+nc, R0=a*a/(b*b), c = 1-(into?-ddn:dot(tdir,n));
  float Re=R0+(1-R0)*c*c*c*c*c,Tr=1-Re,P=.25+.5*Re,RP=Re/P,TP=Tr/(1-P);
  return obj.e + f*(depth>2 ? (random(Xi)<P ?   // Russian roulette
    radiance(reflRay,depth,Xi)*RP:radiance(Ray(x,tdir),depth,Xi)*TP) :
    radiance(reflRay,depth,Xi)*Re+radiance(Ray(x,tdir),depth,Xi)*Tr);
}
kernel void smallpt(
         device float3  *out,
         uint2 id [[ thread_position_in_grid ]]) {
             uint row = id.x;
             uint col = id.y;
             uint index = row*3000 + col;
  int w=1024, h=768, samps = argc==2 ? atoi(argv[1])/4 : 1; // # samples
  Ray cam(float3(50,52,295.6), float3(0,-0.042612,-1).norm()); // cam pos, dir
  float3 cx=float3(w*.5135/h), cy=(cx%cam.d).norm()*.5135, r, *c=new float3[w*h];
  for (int y=0; y<h; y++){                       // Loop over image rows
    float Xi = 0.0;
    for (unsigned short x=0; x<w; x++)   // Loop cols
      for (int sy=0, i=(h-y-1)*w+x; sy<2; sy++)     // 2x2 subpixel rows
        for (int sx=0; sx<2; sx++, r=float3()){        // 2x2 subpixel cols
          for (int s=0; s<samps; s++){
            float r1=2*random(&Xi), dx=r1<1 ? sqrt(r1)-1: 1-sqrt(2-r1);
            float r2=2*random(&Xi), dy=r2<1 ? sqrt(r2)-1: 1-sqrt(2-r2);
            float3 d = cx*( ( (sx+.5 + dx)/2 + x)/w - .5) +
                    cy*( ( (sy+.5 + dy)/2 + y)/h - .5) + cam.d;
            r = r + radiance(Ray(cam.o+d*140,d.norm()),0,&Xi)*(1./samps);
          } // Camera rays are pushed ^^^^^ forward to start in interior
          c[i] = c[i] + float3(clamp(r.x),clamp(r.y),clamp(r.z))*.25;
        }
  }
}
