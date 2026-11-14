using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;

// Synchronous sockets avoid curl's loopback resolver machinery. No application
// credentials are used; UDP sends one ordinary example.com DNS query.
public static class SocketProbe {
 public static int Main(string[] args) {
  try {
   if(args.Length < 3) return 2;
   IPAddress remote=IPAddress.Parse(args[1]);
   bool udp=args[0]=="udp"||args[0]=="udp-send";
   using(var socket=new Socket(remote.AddressFamily,udp?SocketType.Dgram:SocketType.Stream,udp?ProtocolType.Udp:ProtocolType.Tcp)) {
    if(args.Length>3) socket.Bind(new IPEndPoint(IPAddress.Parse(args[3]),0));
    socket.SendTimeout=3000;socket.ReceiveTimeout=3000;
    socket.Connect(new IPEndPoint(remote,int.Parse(args[2])));
    if(udp) {
     byte[] dns={0x43,0x48,1,0,0,1,0,0,0,0,0,0,7,101,120,97,109,112,108,101,3,99,111,109,0,0,1,0,1};
     Console.WriteLine("UDP send accepted: "+socket.Send(dns));
     if(args[0]=="udp") {byte[] response=new byte[4096];int count=socket.Receive(response);if(count<1)return 1;Console.WriteLine("UDP response received: "+count);}
    } else Console.WriteLine("TCP connected");
   }
   return 0;
  } catch(SocketException ex) {
   Console.WriteLine("Socket error "+ex.NativeErrorCode+": "+ex.SocketErrorCode);
   return ex.SocketErrorCode==SocketError.AccessDenied?13:1;
  } catch(Exception ex) {Console.WriteLine(ex.Message);return 2;}
 }
}

public sealed class UdpProbeEcho : IDisposable {
 readonly Socket socket;readonly Thread worker;volatile bool stopped;
 public int Port {get;private set;}
 public UdpProbeEcho(string local) {
  var ip=IPAddress.Parse(local);socket=new Socket(ip.AddressFamily,SocketType.Dgram,ProtocolType.Udp);
  socket.Bind(new IPEndPoint(ip,0));Port=((IPEndPoint)socket.LocalEndPoint).Port;
  worker=new Thread(Run);worker.IsBackground=true;worker.Start();
 }
 void Run() {
  try {while(!stopped) {if(!socket.Poll(250000,SelectMode.SelectRead))continue;byte[] data=new byte[4096];EndPoint sender=new IPEndPoint(IPAddress.Any,0);int n=socket.ReceiveFrom(data,ref sender);socket.SendTo(data,0,n,SocketFlags.None,sender);}}catch(ObjectDisposedException){}catch(SocketException){if(!stopped)throw;}
 }
 public void Dispose(){stopped=true;socket.Close();worker.Join(1000);}
}
