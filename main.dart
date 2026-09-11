main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const SignalApp());

class SignalApp extends StatelessWidget {
  const SignalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'إشارات Binance',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF050B14),
        colorScheme: const ColorScheme.dark(primary: Color(0xFFF0B90B)),
      ),
      home: const HomePage(),
    );
  }
}

class Candle {
  final double open, high, low, close;
  Candle(this.open, this.high, this.low, this.close);
}

class Signal {
  final String side;
  final double entry, sl, tp1, tp2, tp3, strength;
  Signal(this.side, this.entry, this.sl, this.tp1, this.tp2, this.tp3, this.strength);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String symbol = 'ETHUSDT';
  String interval = '5m';
  double price = 0;
  List<Candle> candles = [];
  Signal? signal;
  bool loading = true;
  String status = 'جاري الاتصال بـ Binance...';
  WebSocketChannel? socket;
  StreamSubscription? socketSub;
  Timer? refresh;

  @override
  void initState() {
    super.initState();
    loadMarket();
    connectStream();
    refresh = Timer.periodic(const Duration(seconds: 20), (_) => loadMarket());
  }

  String get restSymbol => symbol.toUpperCase();

  Future<void> loadMarket() async {
    try {
      final uri = Uri.parse('https://api.binance.com/api/v3/klines?symbol=$restSymbol&interval=$interval&limit=100');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as List;
      final list = data.map<Candle>((x) => Candle(
        double.parse(x[1].toString()),
        double.parse(x[2].toString()),
        double.parse(x[3].toString()),
        double.parse(x[4].toString()),
      )).toList();
      if (!mounted) return;
      setState(() {
        candles = list;
        price = list.last.close;
        signal = buildSignal(list);
        loading = false;
        status = 'متصل • ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; status = 'تعذر الاتصال — تحقق من الإنترنت'; });
    }
  }

  void connectStream() {
    socketSub?.cancel();
    socket?.sink.close();
    final url = 'wss://stream.binance.com:9443/ws/${restSymbol.toLowerCase()}@kline_$interval';
    try {
      socket = WebSocketChannel.connect(Uri.parse(url));
      socketSub = socket!.stream.listen((raw) {
        try {
          final d = jsonDecode(raw);
          final k = d['k'];
          final c = double.parse(k['c'].toString());
          if (!mounted) return;
          setState(() {
            price = c;
            if (candles.isNotEmpty) {
              final last = candles.last;
              candles[candles.length - 1] = Candle(last.open, math.max(last.high, c), math.min(last.low, c), c);
              signal = buildSignal(candles);
            }
          });
        } catch (_) {}
      }, onError: (_) {
        if (mounted) setState(() => status = 'إعادة الاتصال...');
      });
    } catch (_) {}
  }

  double ema(List<double> values, int period) {
    if (values.isEmpty) return 0;
    final k = 2 / (period + 1);
    double e = values.take(math.min(period, values.length)).reduce((a,b)=>a+b) / math.min(period, values.length);
    for (var i = math.min(period, values.length); i < values.length; i++) e = values[i] * k + e * (1-k);
    return e;
  }

  double atr(List<Candle> cs, int period) {
    if (cs.length < 2) return 0;
    final trs = <double>[];
    for (var i=1;i<cs.length;i++) {
      final c=cs[i], p=cs[i-1];
      trs.add(math.max(c.high-c.low, math.max((c.high-p.close).abs(), (c.low-p.close).abs())));
    }
    final n=math.min(period, trs.length);
    return trs.sublist(trs.length-n).reduce((a,b)=>a+b)/n;
  }

  Signal buildSignal(List<Candle> cs) {
    if (cs.length < 25) return Signal('WAIT', price, price, price, price, price, 0);
    final closes = cs.map((c)=>c.close).toList();
    final e9=ema(closes,9), e21=ema(closes,21), a=atr(cs,14);
    final entry=closes.last;
    final bullish=e9>e21 && entry>e9;
    final bearish=e9<e21 && entry<e9;
    final dist=math.max(a, entry*0.004);
    if (bullish) return Signal('BUY',entry,entry-dist,entry+dist*1.0,entry+dist*1.8,entry+dist*2.6,math.min(95,68+(e9-e21)/entry*5000));
    if (bearish) return Signal('SELL',entry,entry+dist,entry-dist*1.0,entry-dist*1.8,entry-dist*2.6,math.min(95,68+(e21-e9)/entry*5000));
    return Signal('WAIT',entry,entry,entry,entry,entry,50);
  }

  @override
  void dispose() {
    refresh?.cancel(); socketSub?.cancel(); socket?.sink.close(); super.dispose();
  }

  void chooseSymbol() async {
    final controller=TextEditingController(text: symbol.replaceAll('USDT',''));
    final s=await showDialog<String>(context: context, builder:(c)=>AlertDialog(
      title: const Text('اختر العملة'),
      content: TextField(controller: controller, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText:'مثال: BTC')),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,controller.text.trim().toUpperCase()),child:const Text('تطبيق'))],
    ));
    if(s!=null && s.isNotEmpty){setState(()=>symbol='${s.replaceAll('/USDT','')}USDT'); loading=true; loadMarket(); connectStream();}
  }

  @override
  Widget build(BuildContext context) {
    final s=signal;
    final isBuy=s?.side=='BUY'; final isSell=s?.side=='SELL';
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('إشارات Binance', style: TextStyle(fontWeight: FontWeight.bold)),
        actions:[IconButton(onPressed:chooseSymbol, icon:const Icon(Icons.search)), IconButton(onPressed:loadMarket, icon:const Icon(Icons.refresh))],
      ),
      bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xFF07101C), selectedIndex:1, destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),label:'الرئيسية'),NavigationDestination(icon:Icon(Icons.notifications_active_outlined),label:'الإشارات'),NavigationDestination(icon:Icon(Icons.settings_outlined),label:'الإعدادات')]),
      body: RefreshIndicator(onRefresh:loadMarket, child: ListView(padding:const EdgeInsets.fromLTRB(12,0,12,24), children:[
        Card(color:const Color(0xFF0A1422), child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
          Row(children:[CircleAvatar(backgroundColor:const Color(0xFF1C2940),child:const Icon(Icons.currency_bitcoin)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('$symbol',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(status,style:TextStyle(color:status.startsWith('متصل')?Colors.greenAccent:Colors.orange,fontSize:12))])),Text(price==0?'--':price.toStringAsFixed(price>100?2:6),style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold))]),
          const SizedBox(height:12),
          SizedBox(height:42,child:ListView(scrollDirection:Axis.horizontal,children:['1m','5m','15m','1h','4h','1d'].map((x)=>Padding(padding:const EdgeInsets.only(left:6),child:ChoiceChip(label:Text(x),selected:interval==x,onSelected:(_){setState(()=>interval=x);loadMarket();connectStream();}))).toList())),
        ]))),
        const SizedBox(height:10),
        Card(color:const Color(0xFF08111D), child:SizedBox(height:360,child:loading?const Center(child:CircularProgressIndicator()):Padding(padding:const EdgeInsets.all(8),child:CustomPaint(painter:CandlePainter(candles:candles,signal:s))))),
        const SizedBox(height:10),
        if(s!=null) Card(color:const Color(0xFF0A1422), child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[Icon(isBuy?Icons.arrow_upward:isSell?Icons.arrow_downward:Icons.pause_circle_outline,color:isBuy?Colors.greenAccent:isSell?Colors.redAccent:Colors.amber,size:32),const SizedBox(width:8),Text(isBuy?'إشارة شراء':isSell?'إشارة بيع':'انتظار',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:isBuy?Colors.greenAccent:isSell?Colors.redAccent:Colors.amber)),const Spacer(),Text('${s.strength.toStringAsFixed(0)}%',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))]),
          const SizedBox(height:14),
          infoRow('سعر الدخول',s.entry,isBuy?Colors.greenAccent:Colors.redAccent),
          infoRow('وقف الخسارة (SL)',s.sl,Colors.redAccent),
          infoRow('جني الربح (TP1)',s.tp1,Colors.greenAccent),
          infoRow('جني الربح (TP2)',s.tp2,Colors.greenAccent),
          infoRow('جني الربح (TP3)',s.tp3,Colors.greenAccent),
          const SizedBox(height:10),
          LinearProgressIndicator(value:(s.strength/100).clamp(0,1),minHeight:8,borderRadius:BorderRadius.circular(10)),
          const SizedBox(height:8),const Text('الإشارة تجريبية وليست ضمانًا للربح.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white54,fontSize:12)),
        ]))),
      ])),
    );
  }

  Widget infoRow(String title,double value,Color color)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Text(title),const Spacer(),Text(value.toStringAsFixed(value>100?2:6),style:TextStyle(color:color,fontWeight:FontWeight.bold))]));
}

class CandlePainter extends CustomPainter {
  final List<Candle> candles; final Signal? signal;
  CandlePainter({required this.candles,required this.signal});
  @override
  void paint(Canvas canvas,Size size){
    if(candles.isEmpty)return;
    final visible=candles.length>55?candles.sublist(candles.length-55):candles;
    final minP=visible.map((c)=>c.low).reduce(math.min), maxP=visible.map((c)=>c.high).reduce(math.max); final range=(maxP-minP)==0?1:maxP-minP;
    double y(double p)=>size.height-((p-minP)/range)*(size.height-20)-10;
    final grid=Paint()..color=const Color(0xFF1B2939)..strokeWidth=1;
    for(int i=1;i<6;i++){final yy=size.height*i/6;canvas.drawLine(Offset(0,yy),Offset(size.width,yy),grid);}
    final w=size.width/visible.length;
    for(int i=0;i<visible.length;i++){
      final c=visible[i], x=i*w+w/2, up=c.close>=c.open, p=Paint()..color=up?Colors.greenAccent:Colors.redAccent..strokeWidth=1.4;
      canvas.drawLine(Offset(x,y(c.high)),Offset(x,y(c.low)),p);
      final top=y(math.max(c.open,c.close)), bot=y(math.min(c.open,c.close));
      canvas.drawRect(Rect.fromLTRB(x-w*0.32,top,x+w*0.32,math.max(bot,top+2)),p);
    }
    if(signal!=null && signal!.side!='WAIT'){
      final levels=[(signal!.sl,Colors.redAccent,'SL'),(signal!.entry,Colors.white,'ENTRY'),(signal!.tp1,Colors.greenAccent,'TP1'),(signal!.tp2,Colors.greenAccent,'TP2'),(signal!.tp3,Colors.greenAccent,'TP3')];
      for(final l in levels){final yy=y(l.$1); final lp=Paint()..color=l.$2..strokeWidth=1.5; canvas.drawLine(Offset(0,yy),Offset(size.width,yy),lp); final tp=TextPainter(text:TextSpan(text:' ${l.$3}',style:TextStyle(color:l.$2,fontSize:11,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout(); tp.paint(canvas,Offset(4,yy-15));}
    }
  }
  @override bool shouldRepaint(covariant CandlePainter old)=>true;
}
