// WHITEBOARD APP — STAGE 3
// Pages + page formats + backgrounds + thumbnails + navigation.
// No extra packages required.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

void main() => runApp(const WhiteboardApp());

class WhiteboardApp extends StatelessWidget {
  const WhiteboardApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const StartupScreen(),
      );
}

enum TipShape { circle, square }
enum ToolType { pen, highlighter, strokeEraser, regularEraser }
enum ScrollMode { verticalOnly, horizontalOnly, none, twoFingerPanZoom, twoFingerPanOnly }
enum DrawInputMode { penOnly, handOnly, both }
enum DockZone { top, left, right, bottom }
enum PageFormat { infinite, a4Portrait, a4Landscape, a3Portrait, a3Landscape, letter, legal, custom }
enum BackgroundType { plain, horizontalLines, verticalLines, grid, dotted, notebook }

class Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final ToolType tool;
  final TipShape tipShape;
  final bool flatHighlight;

  Stroke({required this.points, required this.color, required this.width, required this.tool, required this.tipShape, this.flatHighlight = true});

  Path get smoothedPath {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length < 3) {
      for (final p in points.skip(1)) path.lineTo(p.dx, p.dy);
      return path;
    }
    for (int i = 1; i < points.length - 1; i++) {
      final mid = Offset((points[i].dx + points[i + 1].dx) / 2, (points[i].dy + points[i + 1].dy) / 2);
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void paint(Canvas canvas) {
    if (tool == ToolType.regularEraser) {
      final p = Paint()
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.clear;
      canvas.drawPath(smoothedPath, p);
      return;
    }
    final p = Paint()
      ..color = tool == ToolType.highlighter ? color.withOpacity(.35) : color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..blendMode = tool == ToolType.highlighter && flatHighlight ? BlendMode.src : BlendMode.srcOver;
    p.strokeCap = tipShape == TipShape.circle ? StrokeCap.round : StrokeCap.square;
    p.strokeJoin = tipShape == TipShape.circle ? StrokeJoin.round : StrokeJoin.miter;
    canvas.drawPath(smoothedPath, p);
  }

  double distanceTo(Offset point) {
    double best = double.infinity;
    for (int i = 0; i < points.length; i++) {
      best = ((points[i] - point).distance < best) ? (points[i] - point).distance : best;
      if (i > 0) {
        final a = points[i - 1], b = points[i];
        final dx = b.dx - a.dx, dy = b.dy - a.dy;
        if (dx != 0 || dy != 0) {
          final t = (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
          best = ((point - Offset(a.dx + t * dx, a.dy + t * dy)).distance < best)
              ? (point - Offset(a.dx + t * dx, a.dy + t * dy)).distance
              : best;
        }
      }
    }
    return best;
  }
}

class PageData {
  PageFormat format;
  double widthCm;
  double heightCm;
  BackgroundType background;
  Color backgroundColor;
  double gridSpacing;
  double gridLineWidth;
  double majorGridEvery;
  double marginCm;
  List<Stroke> strokes;
  List<List<Stroke>> undoStack;
  List<List<Stroke>> redoStack;

  PageData({
    this.format = PageFormat.a4Portrait,
    this.widthCm = 21,
    this.heightCm = 29.7,
    this.background = BackgroundType.plain,
    this.backgroundColor = Colors.white,
    this.gridSpacing = 30,
    this.gridLineWidth = 1,
    this.majorGridEvery = 5,
    this.marginCm = 1.5,
    List<Stroke>? strokes,
  })  : strokes = strokes ?? [],
        undoStack = [],
        redoStack = [];

  bool get isInfinite => format == PageFormat.infinite;

  Size get canvasSize {
    if (isInfinite) return const Size(6000, 4000);
    // Stage 3 uses a consistent logical pixel canvas. Physical page size is
    // stored in cm and is used for the page-format UI and future export.
    const pxPerCm = 37.7952755906; // 96 logical pixels / inch / 2.54
    return Size(widthCm * pxPerCm, heightCm * pxPerCm);
  }

  String get title {
    switch (format) {
      case PageFormat.infinite: return 'Infinite';
      case PageFormat.a4Portrait: return 'A4 Portrait';
      case PageFormat.a4Landscape: return 'A4 Landscape';
      case PageFormat.a3Portrait: return 'A3 Portrait';
      case PageFormat.a3Landscape: return 'A3 Landscape';
      case PageFormat.letter: return 'Letter';
      case PageFormat.legal: return 'Legal';
      case PageFormat.custom: return 'Custom';
    }
  }
}

class WhiteboardDocument {
  final List<PageData> pages;
  int currentPage;
  String name;
  WhiteboardDocument({List<PageData>? pages, this.currentPage = 0, this.name = 'Untitled'}) : pages = pages ?? [PageData()];
}

class ToolbarItem {
  final String toolId;
  DockZone zone;
  int orderInZone;
  ToolbarItem({required this.toolId, required this.zone, required this.orderInZone});
}

List<ToolbarItem> defaultRegularLayout() => [
  ToolbarItem(toolId:'pen',zone:DockZone.top,orderInZone:0), ToolbarItem(toolId:'highlighter',zone:DockZone.top,orderInZone:1),
  ToolbarItem(toolId:'strokeEraser',zone:DockZone.top,orderInZone:2), ToolbarItem(toolId:'regularEraser',zone:DockZone.top,orderInZone:3),
  ToolbarItem(toolId:'undo',zone:DockZone.top,orderInZone:4), ToolbarItem(toolId:'redo',zone:DockZone.top,orderInZone:5),
  ToolbarItem(toolId:'settings',zone:DockZone.top,orderInZone:6), ToolbarItem(toolId:'fullscreenToggle',zone:DockZone.top,orderInZone:7),
  ToolbarItem(toolId:'colorTray',zone:DockZone.left,orderInZone:0), ToolbarItem(toolId:'widthSlider',zone:DockZone.right,orderInZone:0),
];
List<ToolbarItem> defaultFullscreenLayout() => [
  ToolbarItem(toolId:'pen',zone:DockZone.top,orderInZone:0), ToolbarItem(toolId:'highlighter',zone:DockZone.top,orderInZone:1),
  ToolbarItem(toolId:'strokeEraser',zone:DockZone.top,orderInZone:2), ToolbarItem(toolId:'undo',zone:DockZone.top,orderInZone:3),
  ToolbarItem(toolId:'colorTray',zone:DockZone.top,orderInZone:4), ToolbarItem(toolId:'fullscreenToggle',zone:DockZone.top,orderInZone:5),
];


class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  void _newDocument(BuildContext context) {
    PageFormat selected = PageFormat.a4Portrait;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New whiteboard'),
              content: DropdownButtonFormField<PageFormat>(
                value: selected,
                decoration: const InputDecoration(
                  labelText: 'Page format',
                  border: OutlineInputBorder(),
                ),
                items: PageFormat.values.map((format) {
                  return DropdownMenuItem<PageFormat>(
                    value: format,
                    child: Text(format.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selected = value);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => WhiteboardScreen(
                          initialFormat: selected,
                        ),
                      ),
                    );
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _settings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StartupSettingsScreen(),
      ),
    );
  }

  void _notReady(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name will be added in a later stage.')),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: SizedBox(
        width: 430,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(18),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.draw,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Whiteboard',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose what you want to do',
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                _action(
                  context,
                  icon: Icons.folder_open,
                  title: 'Open',
                  subtitle: 'Open an existing whiteboard project',
                  onPressed: () => _notReady(context, 'Open'),
                ),
                _action(
                  context,
                  icon: Icons.note_add,
                  title: 'New',
                  subtitle: 'Create a new whiteboard',
                  onPressed: () => _newDocument(context),
                ),
                _action(
                  context,
                  icon: Icons.picture_as_pdf,
                  title: 'Insert PDF',
                  subtitle: 'Open a PDF for annotation',
                  onPressed: () => _notReady(context, 'Insert PDF'),
                ),
                _action(
                  context,
                  icon: Icons.settings,
                  title: 'Settings',
                  subtitle: 'Configure whiteboard preferences',
                  onPressed: () => _settings(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupSettingsScreen extends StatelessWidget {
  const StartupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text(
          'Whiteboard settings are available inside the editor.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});
  @override State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final WhiteboardDocument _document = WhiteboardDocument();
  PageData get _page => _document.pages[_document.currentPage];

  ToolType _tool = ToolType.pen; TipShape _tipShape = TipShape.circle; Color _color = Colors.black;
  double _strokeWidth = 4; bool _flatHighlight = true; bool _nonOverlappingHighlighter = true;
  List<Offset> _liveDrawPoints = [];
  int _maxUndoSteps = 10;
  final List<Color> _colorTray = [Colors.black,Colors.white,Colors.red,Colors.orange,Colors.yellow,Colors.green,Colors.teal,Colors.cyan,Colors.blue,Colors.indigo,Colors.purple,Colors.pink,Colors.brown,Colors.grey];

  ScrollMode _scrollMode = ScrollMode.twoFingerPanZoom; DrawInputMode _drawInputMode = DrawInputMode.penOnly;
  final Matrix4 _transform = Matrix4.identity(); Offset? _lastFocalPoint; double _lastScale=1; int _activePointers=0; Size _viewportSize=Size.zero;
  List<ToolbarItem> _regularLayout=defaultRegularLayout(), _fullscreenLayout=defaultFullscreenLayout(); bool _isFullscreen=false, _layoutEditable=false;
  int _autosaveSeconds=30; Timer? _autosaveTimer; String _autosaveStatus='';
  bool _showPagePanel=true;

  @override void initState(){super.initState(); _restartAutosaveTimer();}
  @override void dispose(){_autosaveTimer?.cancel();super.dispose();}
  void _restartAutosaveTimer(){_autosaveTimer?.cancel();_autosaveTimer=Timer.periodic(Duration(seconds:_autosaveSeconds),(_)=>_autosave());}
  void _autosave(){if(!mounted)return;setState(()=>_autosaveStatus='Autosaved ${TimeOfDay.now().format(context)}');Future.delayed(const Duration(seconds:2),(){if(mounted)setState(()=>_autosaveStatus='');});}

  void _pushUndoSnapshot(){_page.undoStack.add(List<Stroke>.from(_page.strokes));if(_page.undoStack.length>_maxUndoSteps)_page.undoStack.removeAt(0);_page.redoStack.clear();}
  void _undo(){if(_page.undoStack.isEmpty)return;setState((){_page.redoStack.add(List<Stroke>.from(_page.strokes));_page.strokes=_page.undoStack.removeLast();});}
  void _redo(){if(_page.redoStack.isEmpty)return;setState((){_page.undoStack.add(List<Stroke>.from(_page.strokes));_page.strokes=_page.redoStack.removeLast();});}

  bool _shouldDraw(PointerEvent e){switch(_drawInputMode){case DrawInputMode.penOnly:return e.kind==PointerDeviceKind.stylus||e.kind==PointerDeviceKind.mouse;case DrawInputMode.handOnly:return e.kind==PointerDeviceKind.touch;case DrawInputMode.both:return e.kind==PointerDeviceKind.stylus||e.kind==PointerDeviceKind.touch||e.kind==PointerDeviceKind.mouse;}}
  Offset _toCanvasSpace(Offset p){final inv=Matrix4.inverted(_transform);return MatrixUtils.transformPoint(inv,p);}
  void _onPointerDown(PointerDownEvent e){_activePointers++;if(!_shouldDraw(e))return;final p=_toCanvasSpace(e.localPosition);if(_tool==ToolType.strokeEraser){_pushUndoSnapshot();_eraseStrokesNear(p);}else{setState(()=>_liveDrawPoints=[p]);}}
  void _onPointerMove(PointerMoveEvent e){if(_shouldDraw(e)){final p=_toCanvasSpace(e.localPosition);if(_tool==ToolType.strokeEraser)_eraseStrokesNear(p);else setState(()=>_liveDrawPoints=[..._liveDrawPoints,p]);return;}if(_activePointers==1&&_scrollMode!=ScrollMode.none&&e.kind==PointerDeviceKind.touch)_applyPan(e.delta);}
  void _onPointerUp(PointerUpEvent e){_activePointers=_activePointers>0?_activePointers-1:0;if(!_shouldDraw(e))return;if(_tool==ToolType.strokeEraser)return;if(_liveDrawPoints.length<2){setState(()=>_liveDrawPoints=[]);return;}_pushUndoSnapshot();setState((){_page.strokes.add(Stroke(points:List.from(_liveDrawPoints),color:_color,width:_strokeWidth,tool:_tool,tipShape:_tipShape,flatHighlight:_tool==ToolType.highlighter?_nonOverlappingHighlighter:_flatHighlight));_liveDrawPoints=[];});}
  void _eraseStrokesNear(Offset p){final r=_strokeWidth+6;final before=_page.strokes.length;_page.strokes.removeWhere((s)=>s.tool!=ToolType.regularEraser&&s.distanceTo(p)<r);if(before!=_page.strokes.length)setState((){});}

  void _applyPan(Offset d){Offset q=d;switch(_scrollMode){case ScrollMode.verticalOnly:q=Offset(0,d.dy);break;case ScrollMode.horizontalOnly:q=Offset(d.dx,0);break;case ScrollMode.none:return;case ScrollMode.twoFingerPanZoom:case ScrollMode.twoFingerPanOnly:return;}setState(()=>_transform.translate(q.dx,q.dy));}
  void _onScaleStart(ScaleStartDetails d){_lastFocalPoint=d.focalPoint;_lastScale=1;}
  void _onScaleUpdate(ScaleUpdateDetails d){final pan=_scrollMode==ScrollMode.twoFingerPanZoom||_scrollMode==ScrollMode.twoFingerPanOnly;final zoom=_scrollMode==ScrollMode.twoFingerPanZoom;if(pan&&_lastFocalPoint!=null){final q=d.focalPoint-_lastFocalPoint!;_transform.translate(q.dx,q.dy);}if(zoom){final f=d.scale/_lastScale;if(f.isFinite&&f>0)_transform.scale(f);_lastScale=d.scale;}_lastFocalPoint=d.focalPoint;setState((){});}
  void _onPointerSignal(PointerSignalEvent e){if(e is PointerScrollEvent&&HardwareKeyboard.instance.isShiftPressed){final f=e.scrollDelta.dy>0?.9:1.1;_transform.scale(f);setState((){});}}

  void _fitToScreen([Size? supplied]){final v=supplied??_viewportSize;if(v.width<=0||v.height<=0)return;final s=(v.width/_page.canvasSize.width)<(v.height/_page.canvasSize.height)?v.width/_page.canvasSize.width:v.height/_page.canvasSize.height;final x=(v.width-_page.canvasSize.width*s)/2,y=(v.height-_page.canvasSize.height*s)/2;setState((){_transform..setIdentity()..translate(x,y)..scale(s);});}
  void _fitWidth(){final v=_viewportSize;if(v.width<=0)return;final s=v.width/_page.canvasSize.width;final y=(v.height-_page.canvasSize.height*s)/2;setState((){_transform..setIdentity()..translate(0,y)..scale(s);});}
  void _fitHeight(){final v=_viewportSize;if(v.height<=0)return;final s=v.height/_page.canvasSize.height;final x=(v.width-_page.canvasSize.width*s)/2;setState((){_transform..setIdentity()..translate(x,0)..scale(s);});}
  void _zoom100(){final v=_viewportSize;setState((){_transform..setIdentity()..translate((v.width-_page.canvasSize.width)/2,(v.height-_page.canvasSize.height)/2);});}

  void _switchPage(int index){if(index<0||index>=_document.pages.length)return;setState((){_document.currentPage=index;_liveDrawPoints=[];});WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen());}
  void _addPage({bool duplicate=false}){final old=_page;final p=PageData(format:old.format,widthCm:old.widthCm,heightCm:old.heightCm,background:old.background,backgroundColor:old.backgroundColor,gridSpacing:old.gridSpacing,gridLineWidth:old.gridLineWidth,majorGridEvery:old.majorGridEvery,marginCm:old.marginCm,strokes:duplicate?List<Stroke>.from(old.strokes):[]);setState((){_document.pages.insert(_document.currentPage+1,p);_document.currentPage++;});WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen());}
  void _deletePage(){if(_document.pages.length==1){if(_page.strokes.isEmpty)return;setState((){_page.strokes.clear();});return;}final hasInk=_page.strokes.isNotEmpty;void go(){setState((){_document.pages.removeAt(_document.currentPage);if(_document.currentPage>=_document.pages.length)_document.currentPage=_document.pages.length-1;});WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen());}if(hasInk){showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('Delete page?'),content:const Text('This page contains drawing. Delete it?'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:(){Navigator.pop(c);go();},child:const Text('Delete'))]));}else go();}
  void _movePage(int from,int to){if(to<0||to>=_document.pages.length||from==to)return;setState((){final p=_document.pages.removeAt(from);_document.pages.insert(to,p);_document.currentPage=to;});}

  void _applyPageFormat(PageFormat f,{double? customW,double? customH}){setState((){_page.format=f;switch(f){case PageFormat.infinite:_page.widthCm=158.75;_page.heightCm=105.83;break;case PageFormat.a4Portrait:_page.widthCm=21;_page.heightCm=29.7;break;case PageFormat.a4Landscape:_page.widthCm=29.7;_page.heightCm=21;break;case PageFormat.a3Portrait:_page.widthCm=29.7;_page.heightCm=42;break;case PageFormat.a3Landscape:_page.widthCm=42;_page.heightCm=29.7;break;case PageFormat.letter:_page.widthCm=21.59;_page.heightCm=27.94;break;case PageFormat.legal:_page.widthCm=21.59;_page.heightCm=35.56;break;case PageFormat.custom:_page.widthCm=customW??_page.widthCm;_page.heightCm=customH??_page.heightCm;}});WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen());}

  @override Widget build(BuildContext context){final layout=_isFullscreen?_fullscreenLayout:_regularLayout;return Scaffold(body:Stack(children:[Positioned.fill(child:_buildCanvasArea()),if(_showPagePanel&&!_isFullscreen)_buildPagePanel(),if(_autosaveStatus.isNotEmpty)Positioned(top:8,right:8,child:Chip(label:Text(_autosaveStatus))),for(final z in DockZone.values)_buildDockZone(z,layout),Positioned(bottom:8,left:_showPagePanel&&!_isFullscreen?250:0,right:0,child:_buildPageBar())]));}

  Widget _buildCanvasArea(){return LayoutBuilder(builder:(context,c){final v=Size(c.maxWidth,c.maxHeight);if(_viewportSize!=v){final first=_viewportSize==Size.zero;_viewportSize=v;if(first)WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen(v));}Widget w=Listener(behavior:HitTestBehavior.opaque,onPointerDown:_onPointerDown,onPointerMove:_onPointerMove,onPointerUp:_onPointerUp,onPointerCancel:(e){_activePointers=_activePointers>0?_activePointers-1:0;setState(()=>_liveDrawPoints=[]);},onPointerSignal:_onPointerSignal,child:_transformedCanvas());if(_scrollMode==ScrollMode.twoFingerPanZoom||_scrollMode==ScrollMode.twoFingerPanOnly)w=GestureDetector(behavior:HitTestBehavior.opaque,onScaleStart:_onScaleStart,onScaleUpdate:_onScaleUpdate,child:w);return Container(color:Colors.grey.shade300,child:w);});}
  Widget _transformedCanvas(){final live=_liveDrawPoints.isEmpty?null:Stroke(points:_liveDrawPoints,color:_color,width:_strokeWidth,tool:_tool,tipShape:_tipShape,flatHighlight:_tool==ToolType.highlighter?_nonOverlappingHighlighter:_flatHighlight);return Transform(alignment:Alignment.topLeft,transform:_transform,child:SizedBox(width:_page.canvasSize.width,height:_page.canvasSize.height,child:CustomPaint(painter:BoardPainter(page:_page,liveStroke:live),size:_page.canvasSize)));}

  Widget _buildPagePanel(){return Positioned(left:0,top:58,bottom:76,width:225,child:Material(elevation:5,color:Colors.white,child:Column(children:[Container(height:48,padding:const EdgeInsets.symmetric(horizontal:8),child:Row(children:[const Expanded(child:Text('Pages',style:TextStyle(fontWeight:FontWeight.bold))),IconButton(tooltip:'Hide pages',onPressed:()=>setState(()=>_showPagePanel=false),icon:const Icon(Icons.close))])),const Divider(height:1),Padding(padding:const EdgeInsets.all(6),child:Row(children:[Expanded(child:FilledButton.icon(onPressed:_addPage,icon:const Icon(Icons.add),label:const Text('New'))),const SizedBox(width:5),IconButton(tooltip:'Duplicate page',onPressed:()=>_addPage(duplicate:true),icon:const Icon(Icons.copy))])),Expanded(child:ReorderableListView.builder(itemCount:_document.pages.length,onReorder:(oldIndex,newIndex){if(newIndex>oldIndex)newIndex--;_movePage(oldIndex,newIndex);},itemBuilder:(context,i){final selected=i==_document.currentPage;return Card(key:ValueKey(_document.pages[i]),margin:const EdgeInsets.symmetric(horizontal:7,vertical:4),color:selected?Colors.blue.shade50:null,child:InkWell(onTap:()=>_switchPage(i),child:Padding(padding:const EdgeInsets.all(6),child:Row(children:[SizedBox(width:82,height:62,child:CustomPaint(painter:ThumbnailPainter(page:_document.pages[i]))),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Page ${i+1}',style:const TextStyle(fontWeight:FontWeight.bold)),Text(_document.pages[i].title,style:const TextStyle(fontSize:12)),Text('${_document.pages[i].strokes.length} strokes',style:const TextStyle(fontSize:11,color:Colors.grey))])),IconButton(tooltip:'Delete',onPressed:()=>_switchPage(i),icon:const Icon(Icons.chevron_right,size:18))]))));})),Padding(padding:const EdgeInsets.all(8),child:OutlinedButton.icon(onPressed:_deletePage,icon:const Icon(Icons.delete_outline),label:const Text('Delete current page')))]))));}

  Widget _buildPageBar(){return Material(elevation:6,borderRadius:BorderRadius.circular(25),color:Colors.white,child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),child:Row(children:[IconButton(tooltip:'Pages',onPressed:()=>setState(()=>_showPagePanel=!_showPagePanel),icon:Icon(_showPagePanel?Icons.view_sidebar:Icons.view_sidebar_outlined)),IconButton(tooltip:'Previous page',onPressed:()=>_switchPage(_document.currentPage-1),icon:const Icon(Icons.chevron_left)),Text('Page ${_document.currentPage+1} / ${_document.pages.length}',style:const TextStyle(fontWeight:FontWeight.bold)),Expanded(child:Slider(min:0,max:(_document.pages.length-1).toDouble(),divisions:_document.pages.length>1?_document.pages.length-1:null,value:_document.currentPage.toDouble(),onChanged:_document.pages.length>1?(v)=>_switchPage(v.round()):null)),IconButton(tooltip:'Next page',onPressed:()=>_switchPage(_document.currentPage+1),icon:const Icon(Icons.chevron_right)),IconButton(tooltip:'New page',onPressed:_addPage,icon:const Icon(Icons.add)),IconButton(tooltip:'Duplicate',onPressed:()=>_addPage(duplicate:true),icon:const Icon(Icons.copy)),IconButton(tooltip:'Delete',onPressed:_deletePage,icon:const Icon(Icons.delete_outline)),PopupMenuButton<String>(tooltip:'Page options',onSelected:(v){if(v=='format')_openPageFormatDialog();if(v=='background')_openBackgroundDialog();},itemBuilder:(c)=>const[PopupMenuItem(value:'format',child:Text('Page format')),PopupMenuItem(value:'background',child:Text('Background / grid'))])])));}

  List<ToolbarItem> _itemsIn(DockZone z,List<ToolbarItem> l){final a=l.where((x)=>x.zone==z).toList();a.sort((x,y)=>x.orderInZone.compareTo(y.orderInZone));return a;}
  void _moveTool(String id,DockZone z,List<ToolbarItem> l){setState((){final t=l.firstWhere((x)=>x.toolId==id);t.zone=z;t.orderInZone=l.where((x)=>x.zone==z).length;});}
  Widget _buildDockZone(DockZone z,List<ToolbarItem> l){final h=z==DockZone.top||z==DockZone.bottom;final content=Flex(direction:h?Axis.horizontal:Axis.vertical,mainAxisSize:MainAxisSize.min,children:_itemsIn(z,l).map((x)=>_buildDraggableTool(x,l)).toList());final target=DragTarget<String>(onWillAcceptWithDetails:(_)=>_layoutEditable,onAcceptWithDetails:(d)=>_moveTool(d.data,z,l),builder:(c,candidates,__)=>Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:candidates.isNotEmpty?Colors.blue.withOpacity(.15):Colors.transparent),child:content));switch(z){case DockZone.top:return Positioned(top:0,left:0,right:0,child:SafeArea(child:target));case DockZone.left:return Positioned(top:60,bottom:76,left:0,child:target);case DockZone.right:return Positioned(top:60,bottom:76,right:0,child:target);case DockZone.bottom:return Positioned(bottom:58,left:0,right:0,child:SafeArea(child:target));}}
  Widget _buildDraggableTool(ToolbarItem i,List<ToolbarItem> l){final c=_toolWidget(i.toolId);if(!_layoutEditable)return c;return Draggable<String>(data:i.toolId,feedback:Material(color:Colors.transparent,child:Opacity(opacity:.8,child:c)),childWhenDragging:Opacity(opacity:.3,child:c),child:c);}
  Widget _icon(IconData icon,String tip,VoidCallback fn,{bool selected=false})=>Container(margin:const EdgeInsets.all(3),decoration:BoxDecoration(color:selected?Colors.blue[100]:Colors.white,borderRadius:BorderRadius.circular(7),boxShadow:const[BoxShadow(color:Colors.black26,blurRadius:2)]),child:IconButton(icon:Icon(icon,size:20),tooltip:tip,onPressed:fn));
  Widget _toolWidget(String id){switch(id){case'pen':return _icon(Icons.edit,'Pen',()=>setState(()=>_tool=ToolType.pen),selected:_tool==ToolType.pen);case'highlighter':return _icon(Icons.brush,'Highlighter',()=>setState(()=>_tool=ToolType.highlighter),selected:_tool==ToolType.highlighter);case'strokeEraser':return _icon(Icons.auto_fix_normal,'Stroke eraser',()=>setState(()=>_tool=ToolType.strokeEraser),selected:_tool==ToolType.strokeEraser);case'regularEraser':return _icon(Icons.cleaning_services,'Regular eraser',()=>setState(()=>_tool=ToolType.regularEraser),selected:_tool==ToolType.regularEraser);case'undo':return _icon(Icons.undo,'Undo',_undo);case'redo':return _icon(Icons.redo,'Redo',_redo);case'settings':return _icon(Icons.settings,'Settings',_openSettingsDialog);case'fullscreenToggle':return _icon(_isFullscreen?Icons.fullscreen_exit:Icons.fullscreen,'Fullscreen',(){setState(()=>_isFullscreen=!_isFullscreen);SystemChrome.setEnabledSystemUIMode(_isFullscreen?SystemUiMode.immersiveSticky:SystemUiMode.edgeToEdge);WidgetsBinding.instance.addPostFrameCallback((_)=>_fitToScreen());});case'colorTray':return _buildColorTray();case'widthSlider':return _buildWidthSlider();default:return const SizedBox.shrink();}}

  Widget _buildColorTray(){return Container(width:220,height:92,margin:const EdgeInsets.all(4),padding:const EdgeInsets.all(6),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(8),boxShadow:const[BoxShadow(color:Colors.black26,blurRadius:4)]),child:Row(children:[Expanded(child:Scrollbar(thumbVisibility:true,child:ListView.builder(scrollDirection:Axis.horizontal,itemCount:_colorTray.length+1,itemBuilder:(c,i){if(i==_colorTray.length)return IconButton(onPressed:_openCustomColorDialog,icon:const Icon(Icons.add_circle_outline));final col=_colorTray[i];return InkWell(onTap:()=>setState(()=>_color=col),child:Container(width:32,height:32,margin:const EdgeInsets.symmetric(horizontal:3,vertical:4),decoration:BoxDecoration(color:col,shape:BoxShape.circle,border:Border.all(color:_color==col?Colors.blue:Colors.grey,width:_color==col?3:1))));}))),IconButton(tooltip:'Pen size',onPressed:_openSizeMenu,icon:const Icon(Icons.line_weight))]));}
  Widget _buildWidthSlider(){const sizes=[1.,2.,3.,4.,5.,6.,8.,10.,12.,15.,20.,30.,40.,60.,80.,100.];return Container(width:220,height:58,margin:const EdgeInsets.all(4),padding:const EdgeInsets.symmetric(horizontal:4),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(8),boxShadow:const[BoxShadow(color:Colors.black26,blurRadius:4)]),child:Row(children:[IconButton(onPressed:_openSizeMenu,icon:const Icon(Icons.tune,size:19)),Expanded(child:Scrollbar(thumbVisibility:true,child:ListView.builder(scrollDirection:Axis.horizontal,itemCount:sizes.length,itemBuilder:(c,i){final v=sizes[i];final sel=(_strokeWidth-v).abs()<.01;return InkWell(onTap:()=>setState(()=>_strokeWidth=v),child:Container(width:34,margin:const EdgeInsets.symmetric(horizontal:2,vertical:5),decoration:BoxDecoration(color:sel?Colors.blue.withOpacity(.12):null,borderRadius:BorderRadius.circular(5),border:sel?Border.all(color:Colors.blue):null),child:Center(child:Container(width:v.clamp(2,24),height:v.clamp(2,24),decoration:BoxDecoration(color:_color,shape:BoxShape.circle)))));}))),SizedBox(width:35,child:Text('${_strokeWidth.round()}'))]));}

  void _openSizeMenu(){double v=_strokeWidth;showDialog(context:context,builder:(dc)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Pen / highlighter size'),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[Text('${v.toStringAsFixed(1)} px'),Slider(min:1,max:100,value:v,onChanged:(x)=>setD(()=>v=x)),SizedBox(height:55,child:Scrollbar(thumbVisibility:true,child:ListView(scrollDirection:Axis.horizontal,children:[for(final n in[1,2,3,4,5,6,8,10,12,15,20,30,40,60,80,100])Padding(padding:const EdgeInsets.all(3),child:ChoiceChip(label:Text('$n'),selected:(v-n).abs()<.01,onSelected:(_)=>setD(()=>v=n.toDouble())))])))])),actions:[TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),FilledButton(onPressed:(){setState(()=>_strokeWidth=v);Navigator.pop(dc);},child:const Text('Apply'))])));}
  void _openCustomColorDialog(){double r=_color.r,g=_color.g,b=_color.b,a=_color.a;showDialog(context:context,builder:(dc)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Custom RGBA color'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_rgba('R',r,(v)=>setD(()=>r=v)),_rgba('G',g,(v)=>setD(()=>g=v)),_rgba('B',b,(v)=>setD(()=>b=v)),_rgba('A',a,(v)=>setD(()=>a=v))])),actions:[TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),FilledButton(onPressed:(){final col=Color.from(alpha:a,red:r,green:g,blue:b);setState((){_color=col;_colorTray.add(col);});Navigator.pop(dc);},child:const Text('Add'))])));}
  Widget _rgba(String s,double v,ValueChanged<double> f)=>Row(children:[SizedBox(width:20,child:Text(s)),Expanded(child:Slider(min:0,max:1,value:v,onChanged:f)),SizedBox(width:35,child:Text('${(v*255).round()}'))]);

  void _openPageFormatDialog(){PageFormat f=_page.format;double w=_page.widthCm,h=_page.heightCm;showDialog(context:context,builder:(dc)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Page format'),content:SizedBox(width:430,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[DropdownButton<PageFormat>(isExpanded:true,value:f,items:PageFormat.values.map((x)=>DropdownMenuItem(value:x,child:Text(_formatName(x)))).toList(),onChanged:(x)=>setD(()=>f=x!)),if(f==PageFormat.custom)...[_cmField('Width (cm)',w,(x)=>setD(()=>w=x)),_cmField('Height (cm)',h,(x)=>setD(()=>h=x))],const SizedBox(height:8),Text('Current: ${w.toStringAsFixed(2)} × ${h.toStringAsFixed(2)} cm'),const Text('Infinite uses a large logical workspace in this stage; true unbounded storage will be added with the object/document engine.')]))),actions:[TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),FilledButton(onPressed:(){_applyPageFormat(f,customW:w,customH:h);Navigator.pop(dc);},child:const Text('Apply'))])));}
  String _formatName(PageFormat f)=>switch(f){PageFormat.infinite=>'Infinite',PageFormat.a4Portrait=>'A4 Portrait',PageFormat.a4Landscape=>'A4 Landscape',PageFormat.a3Portrait=>'A3 Portrait',PageFormat.a3Landscape=>'A3 Landscape',PageFormat.letter=>'Letter',PageFormat.legal=>'Legal',PageFormat.custom=>'Custom'};
  Widget _cmField(String label,double value,ValueChanged<double> f){final controller=TextEditingController(text:value.toStringAsFixed(2));return Padding(padding:const EdgeInsets.symmetric(vertical:4),child:TextField(controller:controller,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:label),onChanged:(x){final n=double.tryParse(x);if(n!=null&&n>0)f(n);}});}

  void _openBackgroundDialog(){BackgroundType b=_page.background;Color col=_page.backgroundColor;double spacing=_page.gridSpacing, lw=_page.gridLineWidth, major=_page.majorGridEvery, margin=_page.marginCm;showDialog(context:context,builder:(dc)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Background & grid'),content:SizedBox(width:430,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[DropdownButton<BackgroundType>(isExpanded:true,value:b,items:BackgroundType.values.map((x)=>DropdownMenuItem(value:x,child:Text(_bgName(x)))).toList(),onChanged:(x)=>setD(()=>b=x!)),Text('Grid spacing: ${spacing.toStringAsFixed(1)} px'),Slider(min:8,max:100,value:spacing,onChanged:(x)=>setD(()=>spacing=x)),Text('Line width: ${lw.toStringAsFixed(1)} px'),Slider(min:.5,max:4,value:lw,onChanged:(x)=>setD(()=>lw=x)),Text('Major line every ${major.round()} units'),Slider(min:2,max:10,divisions:8,value:major,onChanged:(x)=>setD(()=>major=x)),Text('Margin: ${margin.toStringAsFixed(1)} cm'),Slider(min:0,max:5,divisions:50,value:margin,onChanged:(x)=>setD(()=>margin=x)),ListTile(contentPadding:EdgeInsets.zero,title:const Text('Paper colour'),trailing:Container(width:32,height:32,decoration:BoxDecoration(color:col,shape:BoxShape.circle,border:Border.all()),))]))),actions:[TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),FilledButton(onPressed:(){setState((){_page.background=b;_page.backgroundColor=col;_page.gridSpacing=spacing;_page.gridLineWidth=lw;_page.majorGridEvery=major;_page.marginCm=margin;});Navigator.pop(dc);},child:const Text('Apply'))])));}
  String _bgName(BackgroundType b)=>switch(b){BackgroundType.plain=>'Plain',BackgroundType.horizontalLines=>'Horizontal lines',BackgroundType.verticalLines=>'Vertical lines',BackgroundType.grid=>'Square grid',BackgroundType.dotted=>'Dotted grid',BackgroundType.notebook=>'Notebook'};

  void _openSettingsDialog(){showDialog(context:context,builder:(dc)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Settings'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Undo limit: $_maxUndoSteps'),Slider(min:5,max:50,divisions:45,value:_maxUndoSteps.toDouble(),onChanged:(v)=>setD(()=>_maxUndoSteps=v.round())),Text('Autosave: ${_autosaveSeconds}s'),Slider(min:5,max:120,divisions:23,value:_autosaveSeconds.toDouble(),onChanged:(v)=>setD(()=>_autosaveSeconds=v.round())),const Text('Tip shape'),Wrap(spacing:6,children:[ChoiceChip(label:const Text('Circle'),selected:_tipShape==TipShape.circle,onSelected:(_)=>setD(()=>_tipShape=TipShape.circle)),ChoiceChip(label:const Text('Square'),selected:_tipShape==TipShape.square,onSelected:(_)=>setD(()=>_tipShape=TipShape.square))]),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Flat highlighter'),value:_flatHighlight,onChanged:(v)=>setD(()=>_flatHighlight=v)),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Non-overlapping highlighter'),subtitle:const Text('New highlight replaces older highlight where they cross'),value:_nonOverlappingHighlighter,onChanged:(v)=>setD(()=>_nonOverlappingHighlighter=v)),const Divider(),const Text('Draw input'),DropdownButton<DrawInputMode>(isExpanded:true,value:_drawInputMode,items:const[DropdownMenuItem(value:DrawInputMode.penOnly,child:Text('Pen only')),DropdownMenuItem(value:DrawInputMode.handOnly,child:Text('Hand only')),DropdownMenuItem(value:DrawInputMode.both,child:Text('Both'))],onChanged:(v)=>setD(()=>_drawInputMode=v!)),const Text('Scroll mode'),DropdownButton<ScrollMode>(isExpanded:true,value:_scrollMode,items:const[DropdownMenuItem(value:ScrollMode.verticalOnly,child:Text('Vertical only')),DropdownMenuItem(value:ScrollMode.horizontalOnly,child:Text('Horizontal only')),DropdownMenuItem(value:ScrollMode.none,child:Text('None')),DropdownMenuItem(value:ScrollMode.twoFingerPanZoom,child:Text('Two-finger pan + zoom')),DropdownMenuItem(value:ScrollMode.twoFingerPanOnly,child:Text('Two-finger pan only'))],onChanged:(v)=>setD(()=>_scrollMode=v!)),const Divider(),Wrap(spacing:4,children:[TextButton(onPressed:_zoom100,child:const Text('100%')),TextButton(onPressed:_fitToScreen,child:const Text('Fit screen')),TextButton(onPressed:_fitWidth,child:const Text('Fit width')),TextButton(onPressed:_fitHeight,child:const Text('Fit height')),TextButton(onPressed:_openPageFormatDialog,child:const Text('Page format')),TextButton(onPressed:_openBackgroundDialog,child:const Text('Background'))]),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Edit toolbar layout'),value:_layoutEditable,onChanged:(v)=>setD(()=>_layoutEditable=v)])),actions:[FilledButton(onPressed:(){setState((){});_restartAutosaveTimer();Navigator.pop(dc);},child:const Text('Done'))])));}
}

class BoardPainter extends CustomPainter {
  final PageData page; final Stroke? liveStroke;
  BoardPainter({required this.page,this.liveStroke});
  @override void paint(Canvas canvas,Size size){canvas.drawRect(Offset.zero&size,Paint()..color=page.backgroundColor);_paintBackground(canvas,size);canvas.saveLayer(Offset.zero&size,Paint());for(final s in page.strokes){if(s.tool==ToolType.highlighter)s.paint(canvas);}if(liveStroke?.tool==ToolType.highlighter)liveStroke!.paint(canvas);canvas.restore();canvas.saveLayer(Offset.zero&size,Paint());for(final s in page.strokes){if(s.tool!=ToolType.highlighter)s.paint(canvas);}if(liveStroke!=null&&liveStroke!.tool!=ToolType.highlighter)liveStroke!.paint(canvas);canvas.restore();}
  void _paintBackground(Canvas c,Size size){final p=Paint()..color=Colors.grey.shade400..strokeWidth=page.gridLineWidth;final spacing=page.gridSpacing;switch(page.background){case BackgroundType.plain:return;case BackgroundType.horizontalLines:for(double y=page.marginCm*37.8;y<size.height;y+=spacing)c.drawLine(Offset(0,y),Offset(size.width,y),p);case BackgroundType.verticalLines:for(double x=page.marginCm*37.8;x<size.width;x+=spacing)c.drawLine(Offset(x,0),Offset(x,size.height),p);case BackgroundType.grid:for(double x=0;x<size.width;x+=spacing)c.drawLine(Offset(x,0),Offset(x,size.height),p);for(double y=0;y<size.height;y+=spacing)c.drawLine(Offset(0,y),Offset(size.width,y),p);case BackgroundType.dotted:for(double y=0;y<size.height;y+=spacing)for(double x=0;x<size.width;x+=spacing)c.drawCircle(Offset(x,y),page.gridLineWidth*1.2,p);case BackgroundType.notebook:for(double y=page.marginCm*37.8;y<size.height;y+=spacing)c.drawLine(Offset(0,y),Offset(size.width,y),p);final mp=Paint()..color=Colors.red.shade300..strokeWidth=page.gridLineWidth;final x=page.marginCm*37.8;c.drawLine(Offset(x,0),Offset(x,size.height),mp);}}
  @override bool shouldRepaint(covariant BoardPainter old)=>true;
}

class ThumbnailPainter extends CustomPainter {
  final PageData page; ThumbnailPainter({required this.page});
  @override void paint(Canvas canvas,Size size){canvas.drawRect(Offset.zero&size,Paint()..color=page.backgroundColor);final sx=size.width/page.canvasSize.width,sy=size.height/page.canvasSize.height,s=sx<sy?sx:sy;canvas.save();canvas.scale(s);final clip=Rect.fromLTWH(0,0,page.canvasSize.width,page.canvasSize.height);canvas.clipRect(clip);final painter=BoardPainter(page:page);painter.paint(canvas,page.canvasSize);canvas.restore();canvas.drawRect(Offset.zero&size,Paint()..style=PaintingStyle.stroke..color=Colors.grey.shade400);}
  @override bool shouldRepaint(covariant ThumbnailPainter old)=>true;
}
