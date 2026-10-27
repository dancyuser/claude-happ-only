using System;using System.Net;using System.Net.Sockets;using System.Net.Security;using System.Text;using System.IO;
public static class DirectDoh {
 public static string Query(string ip,string host,string path,int index,string local){
  using(var s=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp)){
   s.SetSocketOption(SocketOptionLevel.IP,(SocketOptionName)31,IPAddress.HostToNetworkOrder(index));s.Bind(new IPEndPoint(IPAddress.Parse(local),0));
   var ar=s.BeginConnect(IPAddress.Parse(ip),443,null,null);if(!ar.AsyncWaitHandle.WaitOne(5000))throw new Exception("DNS TCP timeout");s.EndConnect(ar);
   using(var net=new NetworkStream(s,false))using(var tls=new SslStream(net,false)){
    tls.ReadTimeout=5000;tls.WriteTimeout=5000;
    var auth=tls.AuthenticateAsClientAsync(host);if(!auth.Wait(7000))throw new Exception("DNS TLS timeout");auth.GetAwaiter().GetResult();
    var req=Encoding.ASCII.GetBytes("GET "+path+" HTTP/1.1\r\nHost: "+host+"\r\nAccept: application/dns-json\r\nConnection: close\r\n\r\n");tls.Write(req,0,req.Length);
    using(var result=new MemoryStream()){var buf=new byte[4096];int n;while((n=tls.Read(buf,0,buf.Length))>0){result.Write(buf,0,n);if(result.Length>65536)throw new Exception("DNS response too large");}
     var raw=Encoding.UTF8.GetString(result.ToArray());if(!raw.StartsWith("HTTP/1.1 200 "))throw new Exception("DNS HTTPS non-200");
     int start=raw.IndexOf('{'),end=raw.LastIndexOf('}');if(start<0||end<start)throw new Exception("DNS JSON absent");return raw.Substring(start,end-start+1);
    }
   }
  }
 }
}
