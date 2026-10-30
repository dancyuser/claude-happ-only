using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Text;

public sealed class HappOnlyWfp : IDisposable {
 [StructLayout(LayoutKind.Explicit,Size=16)] public struct Value {
  [FieldOffset(0)] public uint type;
  [FieldOffset(8)] public IntPtr ptr;
  [FieldOffset(8)] public uint number;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Blob {public uint size; public IntPtr data;}
 [StructLayout(LayoutKind.Sequential)] public struct Display {public IntPtr name,description;}
 [StructLayout(LayoutKind.Sequential)] public struct SubLayer {public Guid key;public Display display;public uint flags;public IntPtr provider;public Blob data;public ushort weight;}
 [StructLayout(LayoutKind.Sequential)] public struct Condition {public Guid key;public uint match;public Value value;}
 [StructLayout(LayoutKind.Sequential)] public struct Action {public uint type;public Guid key;}
 [StructLayout(LayoutKind.Explicit,Size=16)] public struct Context {[FieldOffset(0)] public ulong raw;[FieldOffset(0)] public Guid key;}
 [StructLayout(LayoutKind.Sequential)] public struct Filter {
  public Guid key;public Display display;public uint flags;public IntPtr provider;public Blob providerData;
  public Guid layer,sublayer;public Value weight;public uint count;public IntPtr conditions;
  public Action action;public Context context;public IntPtr reserved;public ulong id;public Value effectiveWeight;
 }
 [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmEngineOpen0(string server,uint auth,IntPtr identity,IntPtr session,out IntPtr engine);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmEngineClose0(IntPtr engine);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionBegin0(IntPtr e,uint flags);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionCommit0(IntPtr e);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionAbort0(IntPtr e);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterAdd0(IntPtr e,ref Filter f,IntPtr sd,out ulong id);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterGetByKey0(IntPtr e,ref Guid key,out IntPtr f);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterDeleteByKey0(IntPtr e,ref Guid key);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerAdd0(IntPtr e,ref SubLayer s,IntPtr sd);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerDeleteByKey0(IntPtr e,ref Guid key);
 [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmGetAppIdFromFileName0(string path,out IntPtr id);
 [DllImport("fwpuclnt.dll")] static extern void FwpmFreeMemory0(ref IntPtr p);
 static Guid V4=new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82"), V6=new Guid("4a72393b-319f-44bc-84c3-ba54dcb3b6b4");
 static Guid App=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971"), User=new Guid("af043a0a-b34d-4f86-979c-c90371af6e66");
 static Guid Remote=new Guid("b235ae9a-1d64-49b8-a44c-5ff3d9095045"), Port=new Guid("c35a604d-d22b-4e1a-91b4-68f674ee674b"), Protocol=new Guid("3971ef2b-623e-4f9a-8cb1-6e79b806b9a7");
 static Guid Universal=new Guid("8ad768ba-3637-43b5-9a22-c11f9123a701");
 IntPtr engine; bool transaction; public bool VerifyOnly;
 public HappOnlyWfp(){if(IntPtr.Size!=8)throw new Exception("64-bit process required");Check(FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out engine),"EngineOpen");}
 static void Check(uint code,string op){if(code!=0)throw new Exception(op+" failed 0x"+code.ToString("X8"));}
 public void Begin(){Check(FwpmTransactionBegin0(engine,0),"Begin");transaction=true;IntPtr n=Marshal.StringToHGlobalUni("Claude-Happ-Only");try{var s=new SubLayer{key=Universal,display=new Display{name=n},flags=1,weight=65535};uint r=FwpmSubLayerAdd0(engine,ref s,IntPtr.Zero);if(r!=0x80320009)Check(r,"SubLayerAdd");}finally{Marshal.FreeHGlobal(n);}}
 public void Commit(){Check(FwpmTransactionCommit0(engine),"Commit");transaction=false;}
 public void Dispose(){if(transaction)FwpmTransactionAbort0(engine);if(engine!=IntPtr.Zero){FwpmEngineClose0(engine);engine=IntPtr.Zero;}}
 static Guid Key(string text){using(var sha=SHA256.Create()){var h=sha.ComputeHash(Encoding.UTF8.GetBytes("Claude-Happ-WFP-v1|"+text));var b=new byte[16];Array.Copy(h,b,16);return new Guid(b);}}
 static Condition Numeric(Guid key,uint type,uint number){return new Condition{key=key,match=10,value=new Value{type=type,number=number}};}
 public static uint IPv4(string ip){var b=System.Net.IPAddress.Parse(ip).GetAddressBytes();if(b.Length!=4)throw new Exception("IPv4 required");return ((uint)b[0]<<24)|((uint)b[1]<<16)|((uint)b[2]<<8)|b[3];}
 public string[] RestrictProgram(string path,string remote,int port,bool persist){
  IntPtr id;Check(FwpmGetAppIdFromFileName0(path,out id),"GetAppId");
  try{return Restrict("program:"+path.ToLowerInvariant(),new Condition{key=App,value=new Value{type=12,ptr=id}},remote,port,persist);}finally{FwpmFreeMemory0(ref id);}
 }
 public string[] RestrictTag(bool persist){return RestrictTag(10808,persist);}
 public string[] RestrictTag(int proxyPort,bool persist){
  if(proxyPort<1||proxyPort>65535)throw new ArgumentOutOfRangeException("proxyPort");
  var sd=new RawSecurityDescriptor("D:(XA;;CC;;;WD;(Exists POLICYAPPID://ClaudeProxyOnly))");
  var bytes=new byte[sd.BinaryLength];sd.GetBinaryForm(bytes,0);
  IntPtr data=Marshal.AllocHGlobal(bytes.Length),blob=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Blob)));
  try{Marshal.Copy(bytes,0,data,bytes.Length);Marshal.StructureToPtr(new Blob{size=(uint)bytes.Length,data=data},blob,false);
   return Restrict("tag:ClaudeProxyOnly",new Condition{key=User,value=new Value{type=14,ptr=blob}},"127.0.0.1",proxyPort,persist);
  }finally{Marshal.FreeHGlobal(blob);Marshal.FreeHGlobal(data);}
 }
 public string ReservePort(string ownerPath,int port,bool persist){
  IntPtr id;Check(FwpmGetAppIdFromFileName0(ownerPath,out id),"GetAppId");
  try{
   var owner=new Condition{key=App,match=10,value=new Value{type=12,ptr=id}};
   var localPort=new Condition{key=new Guid("0c1ba1af-5765-453f-af22-a8f791ac775b"),value=new Value{type=2,number=(uint)port}};
   return Add("port-owner:"+port+"|"+ownerPath.ToLowerInvariant(),new Guid("1247d66d-0b60-4a15-8d44-7155d0f53a0c"),new[]{localPort,owner},persist);
  }finally{FwpmFreeMemory0(ref id);}
 }
 string[] Restrict(string identity,Condition target,string remote,int port,bool persist){
  var result=new List<string>();
  result.Add(Add(identity+"|v4-address|"+remote,V4,new[]{target,Numeric(Remote,3,IPv4(remote))},persist));
  result.Add(Add(identity+"|v4-port|"+port,V4,new[]{target,Numeric(Port,2,(uint)port)},persist));
  result.Add(Add(identity+"|v4-protocol",V4,new[]{target,Numeric(Protocol,1,6)},persist));
  result.Add(Add(identity+"|v6",V6,new[]{target},persist));
  return result.ToArray();
 }
 string Add(string identity,Guid layer,Condition[] conditions,bool persist){
  Guid key=Key(identity);IntPtr found;
  uint status=FwpmFilterGetByKey0(engine,ref key,out found);
  if(status==0){try{var f=(Filter)Marshal.PtrToStructure(found,typeof(Filter));
   // BFE adds INDEXED (0x40) automatically. All security-bearing fields must still match.
   if(f.action.type!=0x1001||f.layer!=layer||f.sublayer!=Universal||(f.flags&~0x40U)!=(persist?1U:0U)||f.count!=conditions.Length)throw new Exception("Existing filter mismatch "+key+" flags="+f.flags);
   int cs=Marshal.SizeOf(typeof(Condition));
   foreach(var expected in conditions){bool ok=false;for(int i=0;i<f.count;i++){var actual=(Condition)Marshal.PtrToStructure(IntPtr.Add(f.conditions,i*cs),typeof(Condition));if(actual.key==expected.key&&actual.match==expected.match&&SameValue(actual.value,expected.value)){ok=true;break;}}if(!ok)throw new Exception("Existing condition mismatch "+key);}
  }finally{FwpmFreeMemory0(ref found);}return key.ToString();}
  if(status!=0x80320003)Check(status,"FilterGet");
  if(VerifyOnly)throw new Exception("Required filter missing: "+identity);
  IntPtr name=Marshal.StringToHGlobalUni("Claude-Happ-Only: "+identity),mem=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Condition))*conditions.Length);
  try{
   int size=Marshal.SizeOf(typeof(Condition));for(int i=0;i<conditions.Length;i++)Marshal.StructureToPtr(conditions[i],IntPtr.Add(mem,i*size),false);
   var filter=new Filter{key=key,display=new Display{name=name},flags=persist?1U:0U,layer=layer,sublayer=Universal,weight=new Value{type=1,number=15},count=(uint)conditions.Length,conditions=mem,action=new Action{type=0x1001}};
   ulong id;Check(FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id),"FilterAdd "+identity);return key.ToString();
  }finally{Marshal.FreeHGlobal(mem);Marshal.FreeHGlobal(name);}
 }
 static bool SameValue(Value a,Value b){
  if(a.type!=b.type)return false;
  if(a.type==1)return (a.number&255)==(b.number&255);
  if(a.type==2)return (a.number&65535)==(b.number&65535);
  if(a.type==3)return a.number==b.number;
  if(a.type==12||a.type==14){var x=(Blob)Marshal.PtrToStructure(a.ptr,typeof(Blob));var y=(Blob)Marshal.PtrToStructure(b.ptr,typeof(Blob));if(x.size!=y.size||x.size>65536)return false;for(int i=0;i<x.size;i++)if(Marshal.ReadByte(x.data,i)!=Marshal.ReadByte(y.data,i))return false;return true;}
  return false;
 }
 public void Delete(string keyString){Guid k=new Guid(keyString);uint s=FwpmFilterDeleteByKey0(engine,ref k);if(s!=0x80320003)Check(s,"FilterDelete");}
 public void DeleteEmptySubLayer(){Guid k=Universal;Check(FwpmSubLayerDeleteByKey0(engine,ref k),"SubLayerDelete");}
 public string Describe(string keyString){Guid k=new Guid(keyString);IntPtr ptr;Check(FwpmFilterGetByKey0(engine,ref k,out ptr),"FilterGet");try{var f=(Filter)Marshal.PtrToStructure(ptr,typeof(Filter));return k+" persistent="+((f.flags&1)!=0)+" flags=0x"+f.flags.ToString("X")+" layer="+f.layer+" block="+(f.action.type==0x1001)+" conditions="+f.count+" name="+Marshal.PtrToStringUni(f.display.name);}finally{FwpmFreeMemory0(ref ptr);}}
}
