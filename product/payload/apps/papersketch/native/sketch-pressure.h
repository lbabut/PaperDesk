#ifndef PAPER_SKETCH_PRESSURE_H
#define PAPER_SKETCH_PRESSURE_H
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

struct PaperPressure {
    std::array<double,3> anchors{{.15,.5,.95}};
    std::array<std::vector<double>,3> samples;
    bool calibrated=false,active=false;
    int stage=0;
    static bool valid(const std::array<double,3>& a){
        return std::isfinite(a[0])&&std::isfinite(a[1])&&std::isfinite(a[2])&&
            a[0]>=.001&&a[2]<=1&&a[1]-a[0]>=.04&&a[2]-a[1]>=.04&&a[2]-a[0]>=.15;
    }
    void start(){for(auto &v:samples)v.clear();stage=0;active=true;}
    void cancel(){active=false;for(auto &v:samples)v.clear();}
    void collect(double p){if(active&&std::isfinite(p)&&p>0&&p<=1&&samples[stage].size()<4096)samples[stage].push_back(p);}
    bool next(){if(!active||stage>=2||samples[stage].size()<16)return false;++stage;return true;}
    bool candidate(std::array<double,3>& a)const{
        if(!active||stage!=2)return false;
        for(int i=0;i<3;i++){if(samples[i].size()<16)return false;auto sorted=samples[i];std::sort(sorted.begin(),sorted.end());a[i]=sorted[sorted.size()/2];}
        return valid(a);
    }
    double map(double p)const{
        if(!std::isfinite(p))return 0;p=std::clamp(p,0.0,1.0);
        if(!calibrated||p<=0||p>=1)return p;
        const double x[]={0,anchors[0],anchors[1],anchors[2],1};
        const double y[]={0,.15,.5,.95,1};
        for(int i=1;i<5;i++)if(p<=x[i])return x[i]>x[i-1]?y[i-1]+(p-x[i-1])*(y[i]-y[i-1])/(x[i]-x[i-1]):y[i];
        return 1;
    }
};
#endif
