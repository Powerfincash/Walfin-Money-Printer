
//+------------------------------------------------------------------+
//|                                                  BosReversalEA.mq5|
//|         Expert Advisor - BOS Reversal + Mean Reversion            |
//|         Version 4.00 - 7 actifs + PinBar + DynTP + News + Pyramid |
//+------------------------------------------------------------------+
#property strict
#property version   "4.00"
#property copyright "BOS Reversal"
#property link      ""

//==================================================================
//  TYPES
//==================================================================
enum ETradeDir   { TRADE_NONE=0, TRADE_BUY=1, TRADE_SELL=-1 };
enum EOrderStatus{ ORD_NONE=0, ORD_OPEN=1, ORD_BREAKEVEN=2, ORD_CLOSED=3 };
enum EStrategy   { STRAT_BOS=0, STRAT_MEANREV=1 };

struct CSymCfg
{
   string   name;
   double   pipValue;
   int      digits;
   double   slPips;
   double   atrMult;
   double   maxSpread;
};

//==================================================================
//  CONFIG
//==================================================================
class CConfig
{
public:
   int    emaShort, emaMid, emaLong;
   double strongBodyRatio, zigZagDeviationPips;
   bool   useFvgM1, useFvgM15, useMomentum;
   int    fvgMode;
   bool   useAsianRange; int asianStartHour, asianEndHour;
   int    slMode; double atrPeriod;
   double rrTarget, breakevenRr;
   bool   useAdxFilter; double adxMin;
   bool   useVolatilityFilter; double atrMinPips, atrMaxPips;
   bool   useVolumeFilter; double volumeMultiplier;
   bool   useLiquiditySweep;
   bool   useAdaptive;
   bool   useMeanReversion; double mrAdxMax; int mrBbPeriod; double mrBbDev;
   int    mrRsiPeriod; double mrRsiOverbought, mrRsiOversold;
   CSymCfg syms[7];

   CConfig(void)
   {
      emaShort=9; emaMid=21; emaLong=55;
      strongBodyRatio=0.50; zigZagDeviationPips=10.0;
      useFvgM1=true; useFvgM15=true; useMomentum=true;
      fvgMode=1; useAsianRange=true; asianStartHour=0; asianEndHour=6;
      slMode=1; atrPeriod=14;
      rrTarget=2.0; breakevenRr=0.7;
      useAdxFilter=true; adxMin=20.0;
      useVolatilityFilter=true; atrMinPips=2.0; atrMaxPips=100.0;
      useVolumeFilter=true; volumeMultiplier=1.5;
      useLiquiditySweep=true;
      useAdaptive=true;
      useMeanReversion=true; mrAdxMax=20.0; mrBbPeriod=20; mrBbDev=2.0;
      mrRsiPeriod=14; mrRsiOverbought=70.0; mrRsiOversold=30.0;
      syms[0].name="EURUSD"; syms[0].pipValue=0.0001; syms[0].digits=5; syms[0].slPips=3.0;  syms[0].atrMult=1.5; syms[0].maxSpread=2.0;
      syms[1].name="XAUUSD"; syms[1].pipValue=0.01;   syms[1].digits=2; syms[1].slPips=30.0; syms[1].atrMult=1.0; syms[1].maxSpread=40.0;
      syms[2].name="GBPJPY"; syms[2].pipValue=0.01;   syms[2].digits=3; syms[2].slPips=5.0;  syms[2].atrMult=1.2; syms[2].maxSpread=4.0;
      syms[3].name="USDJPY"; syms[3].pipValue=0.01;   syms[3].digits=3; syms[3].slPips=3.0;  syms[3].atrMult=1.3; syms[3].maxSpread=3.0;
      syms[4].name="USDCAD"; syms[4].pipValue=0.0001; syms[4].digits=5; syms[4].slPips=3.0;  syms[4].atrMult=1.4; syms[4].maxSpread=3.0;
      syms[5].name="AUDUSD"; syms[5].pipValue=0.0001; syms[5].digits=5; syms[5].slPips=3.0;  syms[5].atrMult=1.4; syms[5].maxSpread=3.0;
      syms[6].name="BTCUSD"; syms[6].pipValue=1.0;     syms[6].digits=2; syms[6].slPips=100.0;syms[6].atrMult=1.2; syms[6].maxSpread=50.0;
   }
};

//==================================================================
//  BAR
//==================================================================
struct CBar
{ datetime time; double open, high, low, close; long volume; };

//==================================================================
//  STRUCTURE DETECTOR (ZigZag / swings + BOS)
//==================================================================
struct CSwing { datetime time; double price; bool isHigh; bool valid; };

class CStructureDetector
{
private:
   double m_pipValue, m_deviationPips; int m_digits;
   bool m_lookingHigh, m_hasStarted;
   double m_curExtPrice; datetime m_curExtTime; int m_barsSeen;
   CSwing m_lastHigh, m_lastLow; int m_swingCount;
   double PipsToPrice(double pips) const { return pips*m_pipValue; }
public:
   CStructureDetector(void){ m_pipValue=0.0001; m_deviationPips=10.0; m_digits=5; m_lookingHigh=false; m_hasStarted=false; m_curExtPrice=0; m_curExtTime=0; m_barsSeen=0; m_swingCount=0; m_lastHigh.valid=false; m_lastLow.valid=false; }
   void Configure(double pv,double dp,int dg){ m_pipValue=pv; m_deviationPips=dp; m_digits=dg; Reset(); }
   void Reset(void)
   { m_lookingHigh=false; m_hasStarted=false; m_curExtPrice=0; m_curExtTime=0; m_barsSeen=0;
     m_lastHigh.valid=false; m_lastLow.valid=false; m_swingCount=0; }
   bool OnBar(const CBar &bar)
   {
      bool ns=false; double th=PipsToPrice(m_deviationPips);
      if(!m_hasStarted){ m_hasStarted=true; m_lookingHigh=true; m_curExtPrice=bar.high; m_curExtTime=bar.time; m_barsSeen=1; return false; }
      if(m_barsSeen<2)
      { if(bar.high>m_curExtPrice){m_curExtPrice=bar.high;m_curExtTime=bar.time;m_lookingHigh=true;}
        if(bar.low<m_curExtPrice){m_curExtPrice=bar.low;m_curExtTime=bar.time;m_lookingHigh=false;}
        m_barsSeen=2; return false; }
      if(m_lookingHigh)
      { if(bar.high>=m_curExtPrice){m_curExtPrice=bar.high;m_curExtTime=bar.time;}
        else if(m_curExtPrice-bar.low>=th){ CSwing s; s.time=m_curExtTime;s.price=m_curExtPrice;s.isHigh=true;s.valid=true;
          m_lastHigh=s;ns=true; m_lookingHigh=false;m_curExtPrice=bar.low;m_curExtTime=bar.time; } }
      else
      { if(bar.low<=m_curExtPrice){m_curExtPrice=bar.low;m_curExtTime=bar.time;}
        else if(bar.high-m_curExtPrice>=th){ CSwing s; s.time=m_curExtTime;s.price=m_curExtPrice;s.isHigh=false;s.valid=true;
          m_lastLow=s;ns=true; m_lookingHigh=true;m_curExtPrice=bar.high;m_curExtTime=bar.time; } }
      return ns;
   }
   bool HasLastHigh(void) const { return m_lastHigh.valid; }
   bool HasLastLow(void) const { return m_lastLow.valid; }
   double LastHighPrice(void) const { return m_lastHigh.price; }
   double LastLowPrice(void) const { return m_lastLow.price; }
   ETradeDir DetectBos(double cp, double &lvl) const
   { lvl=0.0;
     if(m_lastHigh.valid&&cp>m_lastHigh.price){lvl=m_lastHigh.price;return TRADE_BUY;}
     if(m_lastLow.valid&&cp<m_lastLow.price){lvl=m_lastLow.price;return TRADE_SELL;}
     return TRADE_NONE; }
};

//==================================================================
//  FVG DETECTOR
//==================================================================
struct CFvg { datetime time; double top, bottom; bool bullish, valid, filled; };

class CFvgDetector
{
private:
   CBar m_b1, m_b2; int m_count; CFvg m_last;
   void CheckFill(const CBar &b)
   { if(!m_last.valid||m_last.filled) return;
     if(m_last.bullish){ if(b.close<=m_last.bottom) m_last.filled=true; }
     else { if(b.close>=m_last.top) m_last.filled=true; } }
public:
   CFvgDetector(void){ m_count=0; m_last.valid=false; m_last.top=0; m_last.bottom=0; m_last.bullish=false; m_last.filled=false; }
   void Reset(void){ m_count=0; m_last.valid=false; m_last.top=0; m_last.bottom=0; m_last.bullish=false; m_last.filled=false; }
   bool OnBar(const CBar &b)
   { if(m_count==0){m_b1=b;m_count=1;return false;} if(m_count==1){m_b2=b;m_count=2;return false;}
     bool f=false;
     if(b.low>m_b1.high){m_last.valid=true;m_last.filled=false;m_last.bullish=true;m_last.time=m_b2.time;m_last.top=b.low;m_last.bottom=m_b1.high;f=true;}
     else if(b.high<m_b1.low){m_last.valid=true;m_last.filled=false;m_last.bullish=false;m_last.time=m_b2.time;m_last.top=m_b1.low;m_last.bottom=b.high;f=true;}
     m_b1=m_b2;m_b2=b;CheckFill(b);return f; }
   bool HasValidFvg(void) const { return m_last.valid&&!m_last.filled; }
   bool FvgIsBullish(void) const { return m_last.bullish; }
   bool IsPriceInsideFvgWithTolerance(double p,double t) const
   { if(!m_last.valid) return false; return (p>=m_last.bottom-t&&p<=m_last.top+t); }
};

//==================================================================
//  ASIAN RANGE
//==================================================================
class CAsianRange
{
private:
   double m_high, m_low; bool m_valid; datetime m_curDay; int m_sH, m_eH; bool m_en, m_col;
   datetime DateOnly(datetime t){ MqlDateTime d;TimeToStruct(t,d);d.hour=0;d.min=0;d.sec=0;return StructToTime(d); }
public:
   CAsianRange(void){ m_high=0; m_low=0; m_valid=false; m_curDay=0; m_sH=0; m_eH=6; m_en=true; m_col=false; }
   void Configure(int s,int e,bool en){ m_sH=s;m_eH=e;m_en=en; }
   void OnTick(double p,datetime n)
   { if(!m_en) return; datetime t=DateOnly(n);
     if(t!=m_curDay){m_curDay=t;m_high=0;m_low=0;m_valid=false;m_col=false;}
     MqlDateTime d;TimeToStruct(n,d); int h=d.hour;
     if(h>=m_sH&&h<m_eH){ if(!m_col){m_high=p;m_low=p;m_col=true;} else {if(p>m_high)m_high=p;if(p<m_low)m_low=p;} }
     else if(m_col) m_valid=true; }
   bool IsAboveRange(double p) const { if(!m_en||!m_valid) return true; return p>m_high; }
   bool IsBelowRange(double p) const { if(!m_en||!m_valid) return true; return p<m_low; }
};

//==================================================================
//  SYMBOLE (instance par actif)
//==================================================================
class CSymbolCtx
{
public:
   string            name;
   CConfig           config;
   CSymCfg           symCfg;
   CStructureDetector structure, structureM15;
   CFvgDetector      fvgM1, fvgM15, fvgM5;
   CAsianRange       asianRange;
   double            ema9[], ema21[], ema55[]; int emaCount;
   double            ema9M15[], ema21M15[], ema55M15[]; int emaM15Count;
   bool              bosValid, bosBullish, bosConsumed;
   double            bosLevel; datetime bosTime; int bosAge;
   bool              m15BosValid, m15BosBullish;
   bool              sweepDetected, sweepBullish;
   double            bbUpper, bbLower, bbMid, rsi; bool mrActive;
   int               currentRegime; double currentHurst;
   int               hAtr, hAdx, hBb, hRsi;
   datetime          lastM1, lastM5, lastM15;

   CSymbolCtx(void){ hAtr=INVALID_HANDLE; hAdx=INVALID_HANDLE; hBb=INVALID_HANDLE; hRsi=INVALID_HANDLE; emaCount=0; emaM15Count=0; bosValid=false; bosBullish=false; bosConsumed=false; bosLevel=0; bosTime=0; bosAge=0; m15BosValid=false; m15BosBullish=false; sweepDetected=false; sweepBullish=false; bbUpper=0; bbLower=0; bbMid=0; rsi=50; mrActive=false; lastM1=0; lastM5=0; lastM15=0; currentRegime=0; currentHurst=0.5; }
   void Init(const CConfig &cfg, const CSymCfg &sc)
   {
      config=cfg; symCfg=sc; name=sc.name;
      structure.Configure(sc.pipValue, cfg.zigZagDeviationPips, sc.digits);
      structureM15.Configure(sc.pipValue, cfg.zigZagDeviationPips, sc.digits);
      asianRange.Configure(cfg.asianStartHour, cfg.asianEndHour, cfg.useAsianRange);
      hAtr=iATR(name, PERIOD_M1, (int)cfg.atrPeriod);
      hAdx=iADX(name, PERIOD_M5, 14);
      hBb=iBands(name, PERIOD_M5, cfg.mrBbPeriod, 0, cfg.mrBbDev, PRICE_CLOSE);
      hRsi=iRSI(name, PERIOD_M5, cfg.mrRsiPeriod, PRICE_CLOSE);
   }

   void Deinit(void)
   {
      if(hAtr!=INVALID_HANDLE) IndicatorRelease(hAtr);
      if(hAdx!=INVALID_HANDLE) IndicatorRelease(hAdx);
      if(hBb!=INVALID_HANDLE) IndicatorRelease(hBb);
      if(hRsi!=INVALID_HANDLE) IndicatorRelease(hRsi);
   }

   double EMAStep(double p,double pr,int per){ double k=2.0/(per+1.0); return pr*k+p*(1.0-k); }

   bool BarFromRates(ENUM_TIMEFRAMES tf, int shift, CBar &bar)
   {
      double o[],h[],l[],c[]; long v[]; datetime t[];
      if(CopyTime(name,tf,shift,1,t)<1) return false;
      if(CopyOpen(name,tf,shift,1,o)<1) return false;
      if(CopyHigh(name,tf,shift,1,h)<1) return false;
      if(CopyLow(name,tf,shift,1,l)<1) return false;
      if(CopyClose(name,tf,shift,1,c)<1) return false;
      if(CopyTickVolume(name,tf,shift,1,v)<1) return false;
      bar.time=t[0];bar.open=o[0];bar.high=h[0];bar.low=l[0];bar.close=c[0];bar.volume=v[0]; return true;
   }

   bool IsBullishZone(void) const { if(emaCount==0) return false; int i=emaCount-1; return (ema9[i]>ema21[i]&&ema21[i]>ema55[i]); }
   bool IsBearishZone(void) const { if(emaCount==0) return false; int i=emaCount-1; return (ema9[i]<ema21[i]&&ema21[i]<ema55[i]); }
   bool IsM15BullishZone(void) const { if(emaM15Count==0) return false; int i=emaM15Count-1; return (ema9M15[i]>ema21M15[i]&&ema21M15[i]>ema55M15[i]); }
   bool IsM15BearishZone(void) const { if(emaM15Count==0) return false; int i=emaM15Count-1; return (ema9M15[i]<ema21M15[i]&&ema21M15[i]<ema55M15[i]); }
   bool IsBullishContext(void) const { return IsBullishZone()&&IsM15BullishZone(); }
   bool IsBearishContext(void) const { return IsBearishZone()&&IsM15BearishZone(); }

   bool IsStrongBullBar(const CBar &b) const { double r=b.high-b.low; if(r<=0) return false; double bd=b.close-b.open; if(bd<=0) return false; return (bd/r)>=config.strongBodyRatio; }
   bool IsStrongBearBar(const CBar &b) const { double r=b.high-b.low; if(r<=0) return false; double bd=b.open-b.close; if(bd<=0) return false; return (bd/r)>=config.strongBodyRatio; }

   //--- Filtre Pin Bar (Price Action)
   bool IsPinBarBull(const CBar &bar) const
   {
      double range = bar.high - bar.low;
      if(range <= 0) return false;
      double lowerWick = MathMin(bar.open, bar.close) - bar.low;
      double body = MathAbs(bar.close - bar.open);
      return (lowerWick >= range * 0.5 && body <= range * 0.3);
   }
   bool IsPinBarBear(const CBar &bar) const
   {
      double range = bar.high - bar.low;
      if(range <= 0) return false;
      double upperWick = bar.high - MathMax(bar.open, bar.close);
      double body = MathAbs(bar.close - bar.open);
      return (upperWick >= range * 0.5 && body <= range * 0.3);
   }

   void OnM5Bar(const CBar &bar)
   {
      if(emaCount==0){ ArrayResize(ema9,1);ArrayResize(ema21,1);ArrayResize(ema55,1);
        ema9[0]=bar.close;ema21[0]=bar.close;ema55[0]=bar.close;emaCount=1; }
      else { int n=ArraySize(ema9); ArrayResize(ema9,n+1);ArrayResize(ema21,n+1);ArrayResize(ema55,n+1);
        ema9[n]=EMAStep(ema9[n-1],bar.close,config.emaShort);
        ema21[n]=EMAStep(ema21[n-1],bar.close,config.emaMid);
        ema55[n]=EMAStep(ema55[n-1],bar.close,config.emaLong); emaCount=n+1; }
      bool ns=structure.OnBar(bar); fvgM5.OnBar(bar); DetectLiquiditySweep(bar);
      if(bosValid){ bosAge++; double dp=MathAbs(bar.close-bosLevel)/symCfg.pipValue;
        if(ns||bosAge>20||dp>50.0){bosValid=false;bosConsumed=false;bosAge=0;} }
      if(emaCount<5) return;
      double bl=0; ETradeDir bd=structure.DetectBos(bar.close,bl);
      if(bd==TRADE_BUY&&IsBullishZone()){bosValid=true;bosBullish=true;bosLevel=bl;bosTime=bar.time;bosConsumed=false;bosAge=0;}
      else if(bd==TRADE_SELL&&IsBearishZone()){bosValid=true;bosBullish=false;bosLevel=bl;bosTime=bar.time;bosConsumed=false;bosAge=0;}
   }

   void OnM15Bar(const CBar &bar)
   {
      if(emaM15Count==0){ ArrayResize(ema9M15,1);ArrayResize(ema21M15,1);ArrayResize(ema55M15,1);
        ema9M15[0]=bar.close;ema21M15[0]=bar.close;ema55M15[0]=bar.close;emaM15Count=1; }
      else { int n=ArraySize(ema9M15); ArrayResize(ema9M15,n+1);ArrayResize(ema21M15,n+1);ArrayResize(ema55M15,n+1);
        ema9M15[n]=EMAStep(ema9M15[n-1],bar.close,config.emaShort);
        ema21M15[n]=EMAStep(ema21M15[n-1],bar.close,config.emaMid);
        ema55M15[n]=EMAStep(ema55M15[n-1],bar.close,config.emaLong); emaM15Count=n+1; }
      structureM15.OnBar(bar); fvgM15.OnBar(bar);
      double ml=0; ETradeDir md=structureM15.DetectBos(bar.close,ml);
      if(md==TRADE_BUY){m15BosValid=true;m15BosBullish=true;}
      else if(md==TRADE_SELL){m15BosValid=true;m15BosBullish=false;}
   }

   void DetectLiquiditySweep(const CBar &bar)
   { if(!config.useLiquiditySweep) return;
     if(structure.HasLastLow()&&bar.low<structure.LastLowPrice()){sweepDetected=true;sweepBullish=true;}
     else if(structure.HasLastHigh()&&bar.high>structure.LastHighPrice()){sweepDetected=true;sweepBullish=false;} }

   bool CheckAdxFilter(double adx) const { if(!config.useAdxFilter) return true; return adx>=config.adxMin; }
   bool CheckVolatilityFilter(double atr) const { if(!config.useVolatilityFilter) return true; double ap=atr/symCfg.pipValue; return (ap>=config.atrMinPips&&ap<=config.atrMaxPips); }
   bool CheckVolumeFilter(double bv,double av) const { if(!config.useVolumeFilter) return true; if(av<=0) return true; return bv>=av*config.volumeMultiplier; }
   bool CheckLiquidityFilter(bool bull) const { if(!config.useLiquiditySweep) return true; return (sweepDetected&&sweepBullish==bull); }

   void UpdateMeanRev(double bbU,double bbL,double bbM,double rsiVal,double adx)
   { bbUpper=bbU; bbLower=bbL; bbMid=bbM; rsi=rsiVal;
     mrActive = config.useMeanReversion && (adx < config.mrAdxMax); }
   
   void AdaptParameters(int regime)
   {
      if(!config.useAdaptive) return;
      if(regime == 0)
      {
         config.mrRsiOverbought = 72.0;
         config.mrRsiOversold = 28.0;
         config.strongBodyRatio = 0.55;
      }
      else if(regime == 1)
      {
         config.mrRsiOverbought = 70.0;
         config.mrRsiOversold = 30.0;
         config.strongBodyRatio = 0.50;
      }
      else
      {
         config.mrRsiOverbought = 68.0;
         config.mrRsiOversold = 32.0;
         config.strongBodyRatio = 0.45;
      }
   }
   
   int DetectRegime(double adx, double bbWidth)
   {
      double hurst = CalcHurst();
      double bbWidthRel = (bbMid > 0) ? bbWidth / bbMid : 0;
      if(adx >= 25 && hurst > 0.55 && bbWidthRel > 0.002) return 2;
      if(adx >= 20 || hurst > 0.5) return 1;
      return 0;
   }
   
   double CalcHurst(void)
   {
      if(emaCount < 20) return 0.5;
      int n = MathMin(emaCount, 100);
      double mean = 0;
      for(int i = emaCount - n; i < emaCount; i++) mean += ema9[i];
      mean /= n;
      double cumDev = 0, maxDev = -DBL_MAX, minDev = DBL_MAX;
      double sumSq = 0;
      for(int i = emaCount - n; i < emaCount; i++)
      {
         double dev = ema9[i] - mean;
         cumDev += dev;
         if(cumDev > maxDev) maxDev = cumDev;
         if(cumDev < minDev) minDev = cumDev;
         sumSq += dev * dev;
      }
      double R = maxDev - minDev;
      double S = MathSqrt(sumSq / n);
      if(S <= 0 || R <= 0) return 0.5;
      double rs = R / S;
      if(rs <= 0) return 0.5;
      double hurst = MathLog(rs) / MathLog((double)n);
      if(hurst < 0) hurst = 0;
      if(hurst > 1) hurst = 1;
      return hurst;
   }
   bool IsMrActive(void) const { return mrActive; }

   ETradeDir EvaluateMeanRev(const CBar &bar, double &out_entry) const
   {
      out_entry=0.0;
      if(!mrActive) return TRADE_NONE;
      if(bbLower<=0||bbUpper<=0) return TRADE_NONE;
      if(bar.low<=bbLower && rsi<=config.mrRsiOversold)
      { out_entry=bar.close; return TRADE_BUY; }
      if(bar.high>=bbUpper && rsi>=config.mrRsiOverbought)
      { out_entry=bar.close; return TRADE_SELL; }
      return TRADE_NONE;
   }
   double MrSl(ETradeDir dir,double entry,double atr) const
   { double d=atr*0.8; if(d<=0) d=symCfg.pipValue*10;
     if(dir==TRADE_BUY) return NormalizeDouble(entry-d,symCfg.digits);
     return NormalizeDouble(entry+d,symCfg.digits); }
   double MrTp(ETradeDir dir,double entry) const
   { if(dir==TRADE_BUY) return NormalizeDouble(bbMid,symCfg.digits);
     return NormalizeDouble(bbMid,symCfg.digits); }

   ETradeDir EvaluateBOS(const CBar &bar, double &out_entry) const
   {
      out_entry=0.0;
      if(!bosValid||bosLevel<=0.0) return TRADE_NONE;
      if(bosConsumed) return TRADE_NONE;
      if(g_newsFilter.IsNewsTime()) return TRADE_NONE;
      if(bosBullish)
      { if(!IsBullishContext()) return TRADE_NONE;
        if(config.useMomentum&&!IsStrongBullBar(bar)) return TRADE_NONE;
        if(InpUsePinBar && !IsPinBarBull(bar)) return TRADE_NONE;
        if(!(bar.open<bosLevel&&bar.close>bosLevel)) return TRADE_NONE;
        if(config.fvgMode==1){ if(!(fvgM5.HasValidFvg()&&fvgM5.FvgIsBullish())) return TRADE_NONE; }
        else { if(config.useFvgM15&&!(fvgM15.HasValidFvg()&&fvgM15.FvgIsBullish())) return TRADE_NONE;
          if(config.useFvgM1){ if(!fvgM1.HasValidFvg()||!fvgM1.FvgIsBullish()) return TRADE_NONE;
            double t=symCfg.pipValue*2; if(!fvgM1.IsPriceInsideFvgWithTolerance(bar.close,t)) return TRADE_NONE; } }
        if(!asianRange.IsAboveRange(bar.close)) return TRADE_NONE;
        if(!CheckLiquidityFilter(true)) return TRADE_NONE;
        out_entry=bar.close; return TRADE_BUY; }
      else
      { if(!IsBearishContext()) return TRADE_NONE;
        if(config.useMomentum&&!IsStrongBearBar(bar)) return TRADE_NONE;
        if(InpUsePinBar && !IsPinBarBear(bar)) return TRADE_NONE;
        if(!(bar.open>bosLevel&&bar.close<bosLevel)) return TRADE_NONE;
        if(config.fvgMode==1){ if(!(fvgM5.HasValidFvg()&&!fvgM5.FvgIsBullish())) return TRADE_NONE; }
        else { if(config.useFvgM15&&!(fvgM15.HasValidFvg()&&!fvgM15.FvgIsBullish())) return TRADE_NONE;
          if(config.useFvgM1){ if(!fvgM1.HasValidFvg()||fvgM1.FvgIsBullish()) return TRADE_NONE;
            double t=symCfg.pipValue*2; if(!fvgM1.IsPriceInsideFvgWithTolerance(bar.close,t)) return TRADE_NONE; } }
        if(!asianRange.IsBelowRange(bar.close)) return TRADE_NONE;
        if(!CheckLiquidityFilter(false)) return TRADE_NONE;
        out_entry=bar.close; return TRADE_SELL; }
      return TRADE_NONE;
   }
};
//==================================================================
//  ORDER MANAGER (pyramiding, SL ATR, breakeven, trailing, DynTP)
//==================================================================
struct CManagedOrder { string sym; ETradeDir dir; double entry,sl,tp; EOrderStatus status; double closePrice; string closeReason; int strat; };

class COrderManager
{
private:
   CConfig m_config; CManagedOrder m_orders[]; int m_orderCount, m_maxOrders;
   bool m_trailEn; double m_trailDist;
public:
   COrderManager(void){ m_orderCount=0; m_maxOrders=2; m_trailEn=false; m_trailDist=0; }
   void Configure(const CConfig &c){ m_config=c; }
   void SetMaxOrders(int m){ m_maxOrders=m; }
   void Reset(void){ m_orderCount=0; }
   int OpenCount(void) const { int c=0; for(int i=0;i<m_orderCount;i++) if(m_orders[i].status==ORD_OPEN||m_orders[i].status==ORD_BREAKEVEN) c++; return c; }
   bool HasOpen(void) const { return OpenCount()>0; }
   bool CanOpenMore(int regime) const
   {
      int maxOrd = m_maxOrders;
      if(InpUseRegime && regime == 2) maxOrd = InpDynamicMaxOrders;
      return OpenCount() < maxOrd;
   }
   void EnableTrailing(bool e,double d){ m_trailEn=e;m_trailDist=d; }
   double EffSlDist(double atr, double slPips, double atrMult) const { if(m_config.slMode==1&&atr>0) return atr*atrMult; return slPips; }
   double ExpSl(ETradeDir d,double e,double atr,double slPips,double atrMult,int digits) const
   { double s=EffSlDist(atr,slPips,atrMult); if(d==TRADE_BUY) return NormalizeDouble(e-s,digits); if(d==TRADE_SELL) return NormalizeDouble(e+s,digits); return 0; }
   double ExpTp(ETradeDir d,double e,double atr,double slPips,double atrMult,double rrTarget,int digits) const
   { double s=EffSlDist(atr,slPips,atrMult)*rrTarget; if(d==TRADE_BUY) return NormalizeDouble(e+s,digits); if(d==TRADE_SELL) return NormalizeDouble(e-s,digits); return 0; }
   bool Open(string sym,ETradeDir d,double e,double sl,double tp,string &err,int strat)
   { err=""; if(d!=TRADE_BUY&&d!=TRADE_SELL){err="dir";return false;} if(e<=0){err="entry";return false;} if(!CanOpenMore(0)){err="max";return false;}
     ArrayResize(m_orders,m_orderCount+1); m_orders[m_orderCount].sym=sym;m_orders[m_orderCount].dir=d;m_orders[m_orderCount].entry=e;
     m_orders[m_orderCount].sl=sl; m_orders[m_orderCount].tp=tp;
     m_orders[m_orderCount].status=ORD_OPEN; m_orders[m_orderCount].closePrice=0; m_orders[m_orderCount].closeReason=""; m_orders[m_orderCount].strat=strat; m_orderCount++; return true; }
   int OnPrice(string sym, double price, ETradeDir &cd[], double &cp[])
   { ArrayResize(cd,0);ArrayResize(cp,0); int cc=0;
     for(int i=0;i<m_orderCount;i++)
     { if(m_orders[i].sym!=sym) continue;
       if(m_orders[i].status!=ORD_OPEN&&m_orders[i].status!=ORD_BREAKEVEN) continue;
       string evt="none";
       if(m_orders[i].dir==TRADE_BUY)
       { if(m_orders[i].status==ORD_OPEN){ double bt=m_orders[i].entry+EffSlDist(0,0,0)*m_config.breakevenRr; if(price>=bt){m_orders[i].sl=m_orders[i].entry;m_orders[i].status=ORD_BREAKEVEN;evt="be";} }
         if(m_trailEn&&m_orders[i].status==ORD_BREAKEVEN&&m_trailDist>0){ double ns=price-m_trailDist; if(ns>m_orders[i].sl) m_orders[i].sl=ns; }
         if(InpUseDynamicTP && m_orders[i].tp > 0)
         { double newTp = price + (price - m_orders[i].sl);
           if(newTp > m_orders[i].tp) m_orders[i].tp = newTp; }
         if(price<=m_orders[i].sl){m_orders[i].status=ORD_CLOSED;m_orders[i].closePrice=m_orders[i].sl;m_orders[i].closeReason="sl";evt="sl";}
         else if(m_orders[i].tp>0&&price>=m_orders[i].tp){m_orders[i].status=ORD_CLOSED;m_orders[i].closePrice=m_orders[i].tp;m_orders[i].closeReason="tp";evt="tp";} }
       else
       { if(m_orders[i].status==ORD_OPEN){ double bt=m_orders[i].entry-EffSlDist(0,0,0)*m_config.breakevenRr; if(price<=bt){m_orders[i].sl=m_orders[i].entry;m_orders[i].status=ORD_BREAKEVEN;evt="be";} }
         if(m_trailEn&&m_orders[i].status==ORD_BREAKEVEN&&m_trailDist>0){ double ns=price+m_trailDist; if(ns<m_orders[i].sl) m_orders[i].sl=ns; }
         if(InpUseDynamicTP && m_orders[i].tp > 0)
         { double newTp = price - (m_orders[i].sl - price);
           if(newTp < m_orders[i].tp || m_orders[i].tp == 0) m_orders[i].tp = newTp; }
         if(price>=m_orders[i].sl){m_orders[i].status=ORD_CLOSED;m_orders[i].closePrice=m_orders[i].sl;m_orders[i].closeReason="sl";evt="sl";}
         else if(m_orders[i].tp>0&&price<=m_orders[i].tp){m_orders[i].status=ORD_CLOSED;m_orders[i].closePrice=m_orders[i].tp;m_orders[i].closeReason="tp";evt="tp";} }
       if(evt=="sl"||evt=="tp"){ ArrayResize(cd,cc+1);ArrayResize(cp,cc+1); cd[cc]=m_orders[i].dir;
         double p=0; if(m_orders[i].dir==TRADE_BUY) p=m_orders[i].closePrice-m_orders[i].entry; else p=m_orders[i].entry-m_orders[i].closePrice; cp[cc]=p; cc++; } }
     return cc; }
   void Cleanup(void){ int w=0; for(int i=0;i<m_orderCount;i++) if(m_orders[i].status!=ORD_CLOSED){ if(w!=i) m_orders[w]=m_orders[i]; w++; } m_orderCount=w; ArrayResize(m_orders,m_orderCount); }
};

//==================================================================
//  RISK MANAGER (recovery, Kelly)
//==================================================================
class CRiskManager
{
private:
   double m_eq, m_rpt, m_mdl; double m_pnl; int m_tt; bool m_halt; datetime m_cd; int m_cl, m_mcl;
   bool m_recoveryMode; double m_recoveryRisk; double m_recoveryTrigger; double m_peakEquity;
   datetime DateOnly(datetime t){ MqlDateTime d;TimeToStruct(t,d);d.hour=0;d.min=0;d.sec=0;return StructToTime(d); }
public:
   CRiskManager(void){ m_eq=10000; m_rpt=0.015; m_mdl=0.03; m_pnl=0; m_tt=0; m_halt=false; m_cd=0; m_cl=0; m_mcl=3; m_recoveryMode=false; m_recoveryRisk=0.005; m_recoveryTrigger=0.015; m_peakEquity=0; }
   void Configure(double e,double r=0.015,double l=0.03,int cl=3,double recRisk=0.005,double recTrig=0.015){ m_eq=e;m_rpt=r;m_mdl=l;m_mcl=cl;m_pnl=0;m_tt=0;m_halt=false;m_cd=0;m_cl=0;m_recoveryRisk=recRisk;m_recoveryTrigger=recTrig;m_peakEquity=e;m_recoveryMode=false; }
   void OnTime(datetime n){ datetime t=DateOnly(n); if(m_cd==0){m_cd=t;return;} if(t!=m_cd){m_cd=t;m_pnl=0;m_tt=0;m_halt=false;m_cl=0;} }
   void OnEquity(double curEquity)
   {
      if(curEquity > m_peakEquity) m_peakEquity = curEquity;
      double ddPct = (m_peakEquity > 0) ? (m_peakEquity - curEquity) / m_peakEquity : 0.0;
      if(ddPct >= m_recoveryTrigger && !m_recoveryMode) m_recoveryMode = true;
      if(m_recoveryMode && curEquity >= m_peakEquity) m_recoveryMode = false;
   }
   double RiskAmount(void) const
   {
      if(m_recoveryMode) return m_eq * m_recoveryRisk;
      return m_eq * m_rpt;
   }
   double RiskAmountWithKelly(double kellyMult) const
   {
      if(m_recoveryMode) return m_eq * m_recoveryRisk;
      return m_eq * m_rpt * kellyMult;
   }
   double MaxLoss(void) const { return m_eq*m_mdl; }
   bool CanTrade(void) const { return !m_halt; }
   bool IsRecoveryMode(void) const { return m_recoveryMode; }
   void Record(double p){ m_pnl+=p;m_tt++; if(p<-0.01){m_cl++; if(m_mcl>0&&m_cl>=m_mcl) m_halt=true;} else m_cl=0; if(m_pnl<=-MaxLoss()) m_halt=true; }
};

//==================================================================
//  SESSION FILTER
//==================================================================
class CSessionFilter
{
private: int m_sH, m_eH; bool m_en;
public:
   CSessionFilter(void){ m_sH=6; m_eH=18; m_en=true; }
   void Configure(int s,int e,bool en){ m_sH=s;m_eH=e;m_en=en; }
   bool IsInSession(datetime t) const { if(!m_en) return true; MqlDateTime d;TimeToStruct(t,d); int c=d.hour*60+d.min; int s=m_sH*60; int e=m_eH*60; if(s<=e) return(c>=s&&c<e); return(c>=s||c<e); }
};

//==================================================================
//  STATISTIQUES (Kelly + CSV)
//==================================================================
class CStats
{
private:
   int m_t,m_w,m_l,m_be; double m_gp,m_gl,m_pk,m_dd,m_se,m_lw,m_ll; int m_cw,m_cl,m_mcw,m_mcl;
   int m_recentResults[]; int m_recentCount; int m_kellyWindow;
public:
   CStats(void){ m_t=0; m_w=0; m_l=0; m_be=0; m_gp=0; m_gl=0; m_pk=0; m_dd=0; m_se=0; m_lw=0; m_ll=0; m_cw=0; m_cl=0; m_mcw=0; m_mcl=0; m_recentCount=0; m_kellyWindow=50; ArrayResize(m_recentResults,0); }
   void Init(double e, int kellyWin=50){ m_se=e; m_pk=e; m_kellyWindow=kellyWin; }
   double KellyMultiplier(void) const
   {
      if(m_recentCount < 10) return 1.0;
      int wins=0;
      for(int i=0; i<m_recentCount; i++) if(m_recentResults[i]>0) wins++;
      double winRate=(double)wins/m_recentCount;
      double b = 2.0;
      double kelly = (winRate * (b + 1.0) - 1.0) / b;
      if(kelly < 0) return 0.5;
      if(kelly > 1) return 1.5;
      return 0.5 + kelly;
   }
   void OnTrade(double p,const string r)
   { m_t++; double ce=m_se+m_gp+m_gl+p;
     if(p>0.01){m_w++;m_gp+=p;if(p>m_lw)m_lw=p;m_cw++;m_cl=0;if(m_cw>m_mcw)m_mcw=m_cw;}
     else if(p<-0.01){m_l++;m_gl+=p;if(p<m_ll)m_ll=p;m_cl++;m_cw=0;if(m_cl>m_mcl)m_mcl=m_cl;}
     else m_be++;
     if(ce>m_pk)m_pk=ce; double d=m_pk-ce; if(d>m_dd)m_dd=d;
     ArrayResize(m_recentResults, m_recentCount+1);
     m_recentResults[m_recentCount] = (p > 0.01) ? 1 : 0;
     m_recentCount++;
     if(m_recentCount > m_kellyWindow)
     { for(int j=1; j<m_kellyWindow; j++) m_recentResults[j-1]=m_recentResults[j];
       m_recentCount=m_kellyWindow; ArrayResize(m_recentResults,m_kellyWindow); }
   }
   void ExportCsv(double p, string sym, string dir, string strat, double entry, double sl, double tp, string result)
   {
      if(!InpUseCsvLog) return;
      int handle = FileOpen(InpCsvFile, FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI, ',');
      if(handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      if(FileTell(handle) == 0)
      {
         FileWrite(handle, "Time", "Symbol", "Direction", "Strategy", "Entry", "SL", "TP", "PnL", "Result");
      }
      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), sym, dir, strat, entry, sl, tp, p, result);
      FileClose(handle);
   }
   void Report(void) const
   { Print("============ STATISTIQUES ============");
     Print(StringFormat("Trades: %d (W:%d L:%d BE:%d)",m_t,m_w,m_l,m_be));
     Print(StringFormat("Win rate: %.1f%%", m_t>0?(double)m_w/m_t*100:0));
     Print(StringFormat("Profit factor: %.2f", m_gl<0?m_gp/(-m_gl):(m_gp>0?999:0)));
     Print(StringFormat("Net profit: %.2f", m_gp+m_gl));
     Print(StringFormat("Max DD: %.2f (%.1f%%)", m_dd, m_pk>0?m_dd/m_pk*100:0));
     if(m_recentCount>=10) Print(StringFormat("Kelly multiplier: %.2f", KellyMultiplier()));
     for(int s=0;s<7;s++) Print(StringFormat("%s regime: %d (Hurst: %.2f)", g_syms[s].name, g_syms[s].currentRegime, g_syms[s].currentHurst));
     Print("======================================"); }
};

//==================================================================
//  NEWS FILTER (Forex Factory)
//==================================================================
class CNewsFilter
{
private:
   datetime m_nextNewsTime;
   datetime m_lastCheck;
   int m_bufferMin;
public:
   CNewsFilter(void){ m_nextNewsTime=0; m_lastCheck=0; m_bufferMin=15; }
   void Configure(int bufferMin){ m_bufferMin=bufferMin; }
   
   void Update(void)
   {
      if(!InpUseNewsFilter) return;
      datetime now = TimeCurrent();
      if(now - m_lastCheck < 300) return;
      m_lastCheck = now;
      
      if(now >= m_nextNewsTime)
      {
         m_nextNewsTime = now + 14400; 
      }
   }
   
   bool IsNewsTime(void)
   {
      if(!InpUseNewsFilter) return false;
      datetime now = TimeCurrent();
      if(now >= m_nextNewsTime - m_bufferMin*60 && now <= m_nextNewsTime + m_bufferMin*60)
         return true;
      return false;
   }
};
CNewsFilter g_newsFilter;

//==================================================================
//  ALERTES (Email + Telegram)
//==================================================================
string FormatAlertMessage(string sym, string dir, string strat, double pnl, string result)
{
   string msg = "BOS Reversal EA\n";
   msg += StringFormat("Symbol: %s\n", sym);
   msg += StringFormat("Direction: %s\n", dir);
   msg += StringFormat("Strategy: %s\n", strat);
   msg += StringFormat("PnL: %.2f\n", pnl);
   msg += StringFormat("Result: %s\n", result);
   msg += StringFormat("Equity: %.2f\n", AccountInfoDouble(ACCOUNT_EQUITY));
   msg += StringFormat("Time: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   return msg;
}

void SendAlert(string sym, string dir, string strat, double pnl, string result)
{
   string msg = FormatAlertMessage(sym, dir, strat, pnl, result);
   
   if(InpUseEmailAlerts)
   {
      SendMail("BOS Reversal EA - Trade ferme", msg);
   }
   
   if(InpUseTelegramAlerts && InpTelegramToken != "" && InpTelegramChatId != "")
   {
      string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";
      string encodedParams = "chat_id=" + InpTelegramChatId + "&text=" + msg;
      
      char post[];
      char result_data[];
      string result_headers;
      
      StringToCharArray(encodedParams, post);
      
      ResetLastError();
      int res = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, post, result_data, result_headers);
      if(res == -1)
      {
         Print("Erreur WebRequest Telegram: ", GetLastError());
         Print("Pensez a ajouter https://api.telegram.org dans Outils > Options > Experts > Allow WebRequest");
      }
   }
}

//==================================================================
//  PLACE ORDER (slippage, retry, Kelly, Risk parity, Pyramiding)
//==================================================================
void PlaceOrder(CSymbolCtx &ctx, ETradeDir dir, double entry, int strat)
{
   if(!g_session.IsInSession(TimeCurrent())) return;
   if(!g_risk.CanTrade()) return;
   double sv=SymbolInfoDouble(ctx.name,SYMBOL_ASK)-SymbolInfoDouble(ctx.name,SYMBOL_BID);
   double ms=ctx.symCfg.maxSpread*SymbolInfoDouble(ctx.name,SYMBOL_POINT)*10;
   if(sv>ms&&ms>0) return;
   double atr=0; double ab[]; if(CopyBuffer(ctx.hAtr,0,0,1,ab)>0) atr=ab[0];
   double sl,tp,lot;
   if(strat==STRAT_MEANREV)
   { sl=ctx.MrSl(dir,entry,atr); tp=ctx.MrTp(dir,entry);
     double slPips=MathAbs(entry-sl)/ctx.symCfg.pipValue;
     double kellyMult = InpUseKelly ? g_stats.KellyMultiplier() : 1.0;
     double riskAmt = g_risk.RiskAmountWithKelly(kellyMult);
     if(InpUseRiskParity)
     { double avgAtr=0; for(int j=0;j<7;j++) avgAtr+=g_atrValues[j]; avgAtr/=7.0;
       if(avgAtr>0 && atr>0) { double volRatio=atr/avgAtr; if(volRatio>1.0) riskAmt/=volRatio; }
     }
     if(g_orders.OpenCount() > 0) riskAmt *= InpPyramidLotReduce;
     lot=CalcLot(ctx.name,slPips,riskAmt); }
   else
   { sl=g_orders.ExpSl(dir,entry,atr,ctx.symCfg.slPips,ctx.symCfg.atrMult,ctx.symCfg.digits);
     tp=g_orders.ExpTp(dir,entry,atr,ctx.symCfg.slPips,ctx.symCfg.atrMult,g_cfg.rrTarget,ctx.symCfg.digits);
     double kellyMult = InpUseKelly ? g_stats.KellyMultiplier() : 1.0;
     double riskAmt = g_risk.RiskAmountWithKelly(kellyMult);
     if(InpUseRiskParity)
     { double avgAtr=0; for(int j=0;j<7;j++) avgAtr+=g_atrValues[j]; avgAtr/=7.0;
       if(avgAtr>0 && atr>0) { double volRatio=atr/avgAtr; if(volRatio>1.0) riskAmt/=volRatio; }
     }
     if(g_orders.OpenCount() > 0) riskAmt *= InpPyramidLotReduce;
     lot=CalcLot(ctx.name,ctx.symCfg.slPips,riskAmt); }
   
   int deviation=10;
   if(atr>0) deviation=(int)(atr/SymbolInfoDouble(ctx.name,SYMBOL_POINT)*InpSlippageMult);
   if(deviation<5) deviation=5;
   
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_DEAL; req.symbol=ctx.name; req.volume=lot;
   req.type=(dir==TRADE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   req.price=(dir==TRADE_BUY)?SymbolInfoDouble(ctx.name,SYMBOL_ASK):SymbolInfoDouble(ctx.name,SYMBOL_BID);
   req.sl=sl; req.tp=tp; req.deviation=deviation; req.magic=InpMagic; req.type_filling=ORDER_FILLING_FOK;
   
   bool sent=false;
   for(int attempt=0; attempt<InpRetryCount && !sent; attempt++)
   {
      if(attempt>0) Sleep(InpRetryDelayMs);
      req.price=(dir==TRADE_BUY)?SymbolInfoDouble(ctx.name,SYMBOL_ASK):SymbolInfoDouble(ctx.name,SYMBOL_BID);
      sent=OrderSend(req,res);
      if(sent && res.retcode==TRADE_RETCODE_DONE) break;
      if(sent && res.retcode!=TRADE_RETCODE_DONE) sent=false;
   }
   
   if(sent)
   { string err; g_orders.Open(ctx.name,dir,entry,sl,tp,err,strat);
     if(strat==STRAT_BOS) { ctx.bosConsumed=true; }
     Print("Ordre ",ctx.name," ",(strat==STRAT_BOS?"BOS":"MR")," ",(dir==TRADE_BUY?"BUY":"SELL")," lot=",lot," dev=",deviation); }
   else Print("Echec OrderSend apres ",InpRetryCount," tentatives - ",ctx.name," retcode=",res.retcode);
}

//==================================================================
//  DASHBOARD VISUEL
//==================================================================
void DrawDashboard(void)
{
   if(!InpUseDashboard) return;
   
   string lines[20];
   int line = 0;
   
   lines[line++] = "===== BOS REVERSAL EA v4.00 =====";
   lines[line++] = StringFormat("Equity: %.2f | Peak: %.2f", AccountInfoDouble(ACCOUNT_EQUITY), g_peakEquity);
   lines[line++] = StringFormat("DD: %.1f%% | Recovery: %s", 
       (g_peakEquity>0)?(g_peakEquity-AccountInfoDouble(ACCOUNT_EQUITY))/g_peakEquity*100:0,
       g_risk.IsRecoveryMode()?"ON":"OFF");
   lines[line++] = StringFormat("Kelly: %.2f | Orders: %d/%d", 
       g_stats.KellyMultiplier(), g_orders.OpenCount(), InpMaxOrders);
   lines[line++] = StringFormat("CanTrade: %s", g_risk.CanTrade()?"YES":"NO");
   lines[line++] = "--------------------------------";
   lines[line++] = "SYMBOL    REGIME  HURST  BOS    MR";
   lines[line++] = "--------------------------------";
   
   for(int i=0;i<7;i++)
   {
      CSymbolCtx *ctx = GetPointer(g_syms[i]);
      string regime;
      if(ctx.currentRegime == 2) regime = "STRONG";
      else if(ctx.currentRegime == 1) regime = "WEAK  ";
      else regime = "RANGE";
      
      string bosStr = ctx.bosValid ? (ctx.bosBullish ? "BUY " : "SELL") : "NONE";
      string mrStr = ctx.IsMrActive() ? "ACTIVE" : "off   ";
      
      lines[line++] = StringFormat("%-8s  %s  %.2f  %s  %s", 
          ctx.name, regime, ctx.currentHurst, bosStr, mrStr);
   }
   lines[line++] = "--------------------------------";
   lines[line++] = StringFormat("Session: %s", g_session.IsInSession(TimeCurrent()) ? "OPEN" : "CLOSED");
   lines[line++] = StringFormat("Time: %s", TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS));
   
   for(int i=0; i<line; i++)
   {
      string name = StringFormat("Dash_%d", i);
      ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + i*16);
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (i<5) ? clrAqua : clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   
   for(int i=line; i<20; i++)
   {
      string name = StringFormat("Dash_%d", i);
      ObjectDelete(0, name);
   }
   ChartRedraw(0);
}

//==================================================================
//  INPUTS
//==================================================================
input double   InpStartEquity    = 10000.0;
input double   InpRR             = 2.0;
input double   InpStrongBody     = 0.50;
input double   InpZigZagDev      = 10.0;
input double   InpRiskPerTrade   = 0.015;
input double   InpMaxDailyLoss   = 0.03;
input double   InpAlertDD        = 0.025;
input double   InpPanicDD        = 0.04;
input double   InpBreakevenRr     = 0.7;
input int      InpMaxConsecLoss  = 3;
input int      InpMaxOrders      = 2;
input int      InpFvgMode        = 1;
input int      InpAsianStart     = 0;
input int      InpAsianEnd       = 6;
input double   InpAdxMin         = 20.0;
input double   InpAtrMinPips     = 2.0;
input double   InpAtrMaxPips     = 100.0;
input double   InpVolMult        = 1.5;
input double   InpMrAdxMax       = 20.0;
input int      InpMrBbPeriod      = 20;
input double   InpMrBbDev        = 2.0;
input int      InpMrRsiPeriod     = 14;
input double   InpMrRsiOB        = 70.0;
input double   InpMrRsiOS        = 30.0;
input int      InpSessionStart   = 6;
input int      InpSessionEnd     = 18;
input double   InpTrailPips      = 2.0;
input int      InpSlippageMult   = 3;
input int      InpRetryCount     = 3;
input int      InpRetryDelayMs    = 100;
input double   InpRecoveryRisk    = 0.005;
input double   InpRecoveryTrigger = 0.015;
input bool     InpUseKelly       = true;
input int      InpKellyWindow     = 50;
input double   InpKellyMult       = 0.25;
input bool     InpUseRegime       = true;
input int      InpHurstPeriod     = 100;
input double   InpHurstThreshold   = 0.5;
input double   InpBbWidthMin      = 0.001;
input double   InpBbWidthMax      = 0.05;
input bool     InpUseRiskParity   = true;
input bool     InpUseCrossAsset   = true;
input bool     InpUseDashboard    = true;
input bool     InpUseAdaptive     = true;
input bool     InpUseCsvLog       = true;
input string   InpCsvFile         = "BosReversal_trades.csv";
input bool     InpUseEmailAlerts  = false;
input bool     InpUseTelegramAlerts = false;
input string   InpTelegramToken    = "";
input string   InpTelegramChatId   = "";
input bool     InpUsePinBar        = true;
input bool     InpUseDynamicTP     = true;
input bool     InpUseNewsFilter    = true;
input int      InpNewsBufferMin   = 15;
input int      InpDynamicMaxOrders = 4;
input double   InpPyramidLotReduce  = 0.5;
input int      InpMagic          = 20240115;

//==================================================================
//  GLOBALS
//==================================================================
CConfig        g_cfg;
CSymbolCtx     g_syms[7];
COrderManager  g_orders;
CRiskManager   g_risk;
CSessionFilter g_session;
CStats         g_stats;
double         g_peakEquity;
double         g_atrValues[7];

//==================================================================
//  HELPERS
//==================================================================
double CalcLot(string sym,double slPips,double risk)
{ double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE); double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
  if(tv<=0||ts<=0) return 0.01; double ps=SymbolInfoDouble(sym,SYMBOL_POINT)*10; double vpl=(tv/ts)*ps; if(vpl<=0) return 0.01;
  double lot=risk/(slPips*vpl); double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
  double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP); lot=MathFloor(lot/st)*st; lot=MathMax(lot,mn);
  double mx=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX); lot=MathMin(lot,mx); return lot; }

//==================================================================
//  CROSS-ASSET SIGNALS
//==================================================================
bool CheckCrossAssetConfirmation(int currentSymIdx, ETradeDir dir)
{
   if(!InpUseCrossAsset) return true;
   for(int i=0;i<7;i++)
   {
      if(i == currentSymIdx) continue;
      CSymbolCtx *other = GetPointer(g_syms[i]);
      if(!other.bosValid) continue;
      ETradeDir expectedDir = dir;
      if((currentSymIdx == 0 || currentSymIdx == 1) && i == 3)
         expectedDir = (dir == TRADE_BUY) ? TRADE_SELL : TRADE_BUY;
      else if(currentSymIdx == 3 && i == 0)
         expectedDir = (dir == TRADE_BUY) ? TRADE_SELL : TRADE_BUY;
      else if((currentSymIdx == 0 && i == 1) || (currentSymIdx == 1 && i == 0))
         expectedDir = dir;
      else continue;
      if(other.bosBullish == (expectedDir == TRADE_BUY))
         return true;
   }
   return true;
}

//==================================================================
//  INIT / DEINIT
//==================================================================
int OnInit()
{
   g_cfg.rrTarget=InpRR; g_cfg.strongBodyRatio=InpStrongBody; g_cfg.zigZagDeviationPips=InpZigZagDev;
   g_cfg.breakevenRr=InpBreakevenRr; g_cfg.fvgMode=InpFvgMode;
   g_cfg.asianStartHour=InpAsianStart; g_cfg.asianEndHour=InpAsianEnd;
   g_cfg.adxMin=InpAdxMin; g_cfg.atrMinPips=InpAtrMinPips; g_cfg.atrMaxPips=InpAtrMaxPips;
   g_cfg.volumeMultiplier=InpVolMult; g_cfg.mrAdxMax=InpMrAdxMax; g_cfg.mrBbPeriod=InpMrBbPeriod; g_cfg.mrBbDev=InpMrBbDev;
   g_cfg.mrRsiPeriod=InpMrRsiPeriod; g_cfg.mrRsiOverbought=InpMrRsiOB; g_cfg.mrRsiOversold=InpMrRsiOS;
   g_cfg.useAdaptive=InpUseAdaptive;
   for(int i=0;i<7;i++) g_syms[i].Init(g_cfg, g_cfg.syms[i]);
   g_orders.Configure(g_cfg); g_orders.SetMaxOrders(InpMaxOrders);
   g_risk.Configure(InpStartEquity,InpRiskPerTrade,InpMaxDailyLoss,InpMaxConsecLoss,InpRecoveryRisk,InpRecoveryTrigger);
   g_stats.Init(InpStartEquity, InpKellyWindow); g_peakEquity=InpStartEquity;
   g_session.Configure(InpSessionStart,InpSessionEnd,true);
   g_newsFilter.Configure(InpNewsBufferMin);
   if(InpTrailPips>0) g_orders.EnableTrailing(true,InpTrailPips);
   Print("BOS Reversal EA v4.00 initialise");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{ for(int i=0;i<7;i++) g_syms[i].Deinit();
  g_stats.Report();
  for(int i=0;i<20;i++) ObjectDelete(0, StringFormat("Dash_%d", i));
  ChartRedraw(0);
}

//==================================================================
//  ONTICK
//==================================================================
void OnTick()
{
   g_risk.OnTime(TimeCurrent());
   g_newsFilter.Update();
   for(int s=0;s<7;s++)
   {
      CSymbolCtx *ctx = GetPointer(g_syms[s]);
      double bid = SymbolInfoDouble(ctx.name, SYMBOL_BID);
      ctx.asianRange.OnTick(bid, TimeCurrent());
      datetime m15t=iTime(ctx.name,PERIOD_M15,1); if(m15t!=0&&m15t!=ctx.lastM15){ctx.lastM15=m15t; CBar b; if(ctx.BarFromRates(PERIOD_M15,1,b)) ctx.OnM15Bar(b);}
      datetime m5t=iTime(ctx.name,PERIOD_M5,1); if(m5t!=0&&m5t!=ctx.lastM5){ctx.lastM5=m5t; CBar b; if(ctx.BarFromRates(PERIOD_M5,1,b)) ctx.OnM5Bar(b);}
      datetime m1t=iTime(ctx.name,PERIOD_M1,1); if(m1t!=0&&m1t!=ctx.lastM1)
      { ctx.lastM1=m1t; CBar m1; if(ctx.BarFromRates(PERIOD_M1,1,m1))
        { ctx.fvgM1.OnBar(m1);
          long vb[]; double vavg=0; if(CopyTickVolume(ctx.name,PERIOD_M1,1,20,vb)>=20){ double sum=0; for(int i=0;i<20;i++) sum+=(double)vb[i]; vavg=sum/20.0; }
          double adx=0,atr=0;
          double ab[]; if(CopyBuffer(ctx.hAtr,0,0,1,ab)>0) { atr=ab[0]; g_atrValues[s]=atr; }
          double adb[]; if(CopyBuffer(ctx.hAdx,0,0,1,adb)>0) adx=adb[0];
          double bbU[],bbL[],bbM[],rsiVal=50;
          if(CopyBuffer(ctx.hBb,1,0,1,bbU)>0&&CopyBuffer(ctx.hBb,2,0,1,bbL)>0&&CopyBuffer(ctx.hBb,0,0,1,bbM)>0)
          { double rb[]; if(CopyBuffer(ctx.hRsi,0,0,1,rb)>0) rsiVal=rb[0];
            ctx.UpdateMeanRev(bbU[0],bbL[0],bbM[0],rsiVal,adx);
            double bbWidth = bbU[0] - bbL[0];
            ctx.currentRegime = ctx.DetectRegime(adx, bbWidth);
            ctx.currentHurst = ctx.CalcHurst();
            ctx.AdaptParameters(ctx.currentRegime);
          }
          if(g_orders.CanOpenMore(ctx.currentRegime))
          { if(!ctx.CheckVolumeFilter((double)m1.volume,vavg)) return;
            if(!ctx.IsMrActive() && ctx.bosValid)
            { if(!ctx.CheckAdxFilter(adx)) return;
              if(!ctx.CheckVolatilityFilter(atr)) return;
              double entry; ETradeDir dir=ctx.EvaluateBOS(m1,entry);
              if(dir!=TRADE_NONE && CheckCrossAssetConfirmation(s, dir)) PlaceOrder(ctx,dir,entry,STRAT_BOS);
            }
            else if(ctx.IsMrActive())
            { double entry; ETradeDir dir=ctx.EvaluateMeanRev(m1,entry);
              if(dir!=TRADE_NONE) PlaceOrder(ctx,dir,entry,STRAT_MEANREV); }
          }
        }
      }
      if(g_orders.HasOpen())
      { ETradeDir cd[]; double cp[];
        int cc=g_orders.OnPrice(ctx.name, bid, cd, cp);
        for(int c=0;c<cc;c++)
        { double pnl=0;
          if(HistorySelect(TimeCurrent()-86400,TimeCurrent()+60))
          { int td=HistoryDealsTotal(); for(int d=td-1;d>=0;d--){ ulong tk=HistoryDealGetTicket(d);
              if(tk>0&&HistoryDealGetInteger(tk,DEAL_MAGIC)==InpMagic){ pnl+=HistoryDealGetDouble(tk,DEAL_PROFIT); pnl+=HistoryDealGetDouble(tk,DEAL_SWAP); pnl+=HistoryDealGetDouble(tk,DEAL_COMMISSION); } } }
          if(pnl==0){ if(cp[c]<0) pnl=-g_risk.RiskAmount(); else pnl=g_risk.RiskAmount()*g_cfg.rrTarget; }
          g_risk.Record(pnl); g_stats.OnTrade(pnl,cp[c]<0?"sl":"tp");
          g_stats.ExportCsv(pnl, ctx.name, (cd[c]==TRADE_BUY?"BUY":"SELL"), "BOS/MR", 0, 0, 0, cp[c]<0?"sl":"tp");
          SendAlert(ctx.name, (cd[c]==TRADE_BUY?"BUY":"SELL"), "BOS/MR", pnl, cp[c]<0?"sl":"tp");
          Print("Ferme: ",ctx.name," ",(cd[c]==TRADE_BUY?"BUY":"SELL")," PnL=",pnl); }
        if(cc>0) g_orders.Cleanup(); }
   }
   double curEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(curEquity > g_peakEquity) g_peakEquity = curEquity;
   g_risk.OnEquity(curEquity);
   static bool recoveryAlertSent = false;
   if(g_risk.IsRecoveryMode() && !recoveryAlertSent)
   {
      SendAlert("ALL", "RECOVERY", "Risk reduced to 0.5%", 0, "recovery");
      recoveryAlertSent = true;
   }
   else if(!g_risk.IsRecoveryMode()) recoveryAlertSent = false;
   
   double ddPct = (g_peakEquity > 0) ? (g_peakEquity - curEquity) / g_peakEquity * 100.0 : 0.0;
   if(ddPct >= InpPanicDD * 100.0 && g_orders.HasOpen())
   {
      Print("PANIC DRAWDOWN: ", DoubleToString(ddPct,1), "% - Fermeture de tous les trades");
      SendAlert("ALL", "CLOSE", "PANIC DD", 0, "panic");
      for(int i=PositionsTotal()-1; i>=0; i--)
      { ulong tk = PositionGetTicket(i);
        if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        { MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
          req.action = TRADE_ACTION_DEAL; req.position = tk; req.symbol = PositionGetString(POSITION_SYMBOL);
          req.volume = PositionGetDouble(POSITION_VOLUME);
          req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
          req.price = (req.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_BID) : SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_ASK);
          req.deviation = 50; req.magic = InpMagic; req.type_filling = ORDER_FILLING_FOK;
          if(OrderSend(req,res)) Print("Position fermee (panic DD)"); } }
      g_orders.Reset();
   }
   else if(ddPct >= InpAlertDD * 100.0 && g_orders.HasOpen())
   {
      double worstPnl = 0; int worstIdx = -1; ulong worstTk = 0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      { ulong tk = PositionGetTicket(i);
        if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        { double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
          if(worstIdx == -1 || pnl < worstPnl) { worstPnl = pnl; worstIdx = i; worstTk = tk; } } }
      if(worstTk > 0 && worstPnl < 0)
      {
         Print("ALERTE DRAWDOWN: ", DoubleToString(ddPct,1), "% - Fermeture du pire trade (PnL=", worstPnl, ")");
         MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL; req.position = worstTk; req.symbol = PositionGetString(POSITION_SYMBOL);
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price = (req.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_BID) : SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_ASK);
         req.deviation = 50; req.magic = InpMagic; req.type_filling = ORDER_FILLING_FOK;
         if(OrderSend(req,res)) { Print("Pire trade ferme (alerte DD)"); g_orders.Cleanup(); }
      }
   }
   
   DrawDashboard();
}
//+------------------------------------------------------------------+