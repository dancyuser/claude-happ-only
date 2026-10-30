using System;
using System.Runtime.InteropServices;
using System.ComponentModel;
public static class ReadAppIdToken {
 [StructLayout(LayoutKind.Sequential)] struct Unicode {public ushort Length,MaximumLength;public IntPtr Buffer;}
 [StructLayout(LayoutKind.Sequential)] struct Info {public ushort Version,Reserved;public uint Count;public IntPtr Attributes;}
 [StructLayout(LayoutKind.Sequential)] struct Attribute {public Unicode Name;public ushort Type,Reserved;public uint Flags,Count;public IntPtr Values;}
 public sealed class Result {public int ProcessId;public bool HasTag;public string TagValue="";public uint Flags;public bool NonInheritable;public string Error="";}
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int id);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,uint size,out uint needed);
 static void Bounds(IntPtr pointer,long length,IntPtr buffer,uint size){long start=pointer.ToInt64(),low=buffer.ToInt64();if(length<0||start<low||start>low+size-length)throw new Exception("Token attribute outside buffer");}
 static string ReadUnicode(Unicode text,IntPtr buffer,uint size){if(text.Length==0)return "";if(text.Length>8192||(text.Length%2)!=0)throw new Exception("Invalid token string length");Bounds(text.Buffer,text.Length,buffer,size);return Marshal.PtrToStringUni(text.Buffer,text.Length/2);}
 public static Result Query(int processId){
  var result=new Result{ProcessId=processId};IntPtr process=IntPtr.Zero,token=IntPtr.Zero,buffer=IntPtr.Zero;
  try{
   if(IntPtr.Size!=8)throw new Exception("64-bit reader required");
   process=OpenProcess(0x1000,false,processId);if(process==IntPtr.Zero)throw new Win32Exception();
   if(!OpenProcessToken(process,8,out token))throw new Win32Exception();
   uint size;GetTokenInformation(token,39,IntPtr.Zero,0,out size);
   if(size<16||size>1048576)throw new Exception("TokenSecurityAttributes unavailable or invalid size");
   buffer=Marshal.AllocHGlobal((int)size);uint used;
   if(!GetTokenInformation(token,39,buffer,size,out used))throw new Win32Exception();
   var info=(Info)Marshal.PtrToStructure(buffer,typeof(Info));if(info.Version!=1||info.Count>4096)throw new Exception("Unsupported token attributes");
   int stride=Marshal.SizeOf(typeof(Attribute));if(info.Count>0)Bounds(info.Attributes,(long)stride*info.Count,buffer,size);
   for(int i=0;i<info.Count;i++){
    var attribute=(Attribute)Marshal.PtrToStructure(IntPtr.Add(info.Attributes,i*stride),typeof(Attribute));
    if(!String.Equals(ReadUnicode(attribute.Name,buffer,size),"POLICYAPPID://ClaudeProxyOnly",StringComparison.OrdinalIgnoreCase))continue;
    result.HasTag=true;result.Flags=attribute.Flags;result.NonInheritable=(attribute.Flags&1)!=0;
    if(attribute.Type==3&&attribute.Count>0&&attribute.Count<4096){Bounds(attribute.Values,Marshal.SizeOf(typeof(Unicode)),buffer,size);result.TagValue=ReadUnicode((Unicode)Marshal.PtrToStructure(attribute.Values,typeof(Unicode)),buffer,size);}
   }
  }catch(Exception e){result.Error=e.Message;}finally{if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);if(token!=IntPtr.Zero)CloseHandle(token);if(process!=IntPtr.Zero)CloseHandle(process);}
  return result;
 }
}
