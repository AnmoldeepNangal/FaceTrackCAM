using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;

// Local-only USB forwarding through Apple's installed Mobile Device service.
public static class FacePullBridge {
    static readonly SemaphoreSlim Slots = new SemaphoreSlim(8);
    static byte[] ReadExact(Stream stream, int count) {
        var data = new byte[count]; int offset = 0;
        while (offset < count) { int n = stream.Read(data, offset, count - offset); if (n == 0) throw new IOException("USB disconnected"); offset += n; }
        return data;
    }
    static XmlDocument Exchange(NetworkStream stream, string body) {
        var data = Encoding.UTF8.GetBytes("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>ClientVersionString</key><string>FacePull 2.1</string><key>ProgName</key><string>FacePull</string><key>kLibUSBMuxVersion</key><integer>3</integer>" + body + "</dict></plist>");
        using (var writer = new BinaryWriter(stream, Encoding.UTF8, true)) { writer.Write(data.Length + 16); writer.Write(1); writer.Write(8); writer.Write(1); writer.Write(data); writer.Flush(); }
        var header = ReadExact(stream, 16); int length = BitConverter.ToInt32(header, 0);
        if (length < 16 || length > 1048576 || BitConverter.ToInt32(header, 4) != 1 || BitConverter.ToInt32(header, 8) != 8) throw new IOException("Invalid USB response");
        var xml = new XmlDocument(); xml.XmlResolver = null;
        using (var reader = XmlReader.Create(new MemoryStream(ReadExact(stream, length - 16)), new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null })) xml.Load(reader);
        return xml;
    }
    static XmlNode Value(XmlNode dict, string key) {
        if (dict == null) return null;
        foreach (XmlNode node in dict.ChildNodes) if (node.Name == "key" && node.InnerText == key) return node.NextSibling;
        return null;
    }
    static TcpClient OpenMux(int port) {
        var client = new TcpClient();
        try { if (!client.ConnectAsync(IPAddress.Loopback, port).Wait(3000)) throw new IOException("Apple device service unavailable"); client.ReceiveTimeout = 5000; client.SendTimeout = 5000; client.NoDelay = true; return client; }
        catch { client.Close(); throw; }
    }
    static int Device(int muxPort, string serial) {
        using (var client = OpenMux(muxPort)) {
            var xml = Exchange(client.GetStream(), "<key>MessageType</key><string>ListDevices</string>");
            var list = Value(xml.SelectSingleNode("/plist/dict"), "DeviceList");
            int selected = -1, count = 0;
            if (list != null) foreach (XmlNode entry in list.ChildNodes) {
                var props = Value(entry, "Properties"); var kind = Value(props, "ConnectionType"); var id = Value(entry, "DeviceID"); var sn = Value(props, "SerialNumber");
                if (kind == null || kind.InnerText != "USB" || id == null) continue;
                if (!String.IsNullOrEmpty(serial) && (sn == null || sn.InnerText != serial)) continue;
                selected = Int32.Parse(id.InnerText); count++;
            }
            if (count != 1) throw new IOException("Connect one trusted iPhone, or configure DeviceID");
            return selected;
        }
    }
    static async Task Forward(TcpClient obs, int muxPort, string serial) {
        TcpClient phone = null;
        try {
            int id = Device(muxPort, serial); phone = OpenMux(muxPort);
            int port = ((8080 & 255) << 8) | (8080 >> 8);
            var xml = Exchange(phone.GetStream(), "<key>MessageType</key><string>Connect</string><key>DeviceID</key><integer>" + id + "</integer><key>PortNumber</key><integer>" + port + "</integer>");
            var result = Value(xml.SelectSingleNode("/plist/dict"), "Number");
            if (result == null || result.InnerText != "0") throw new IOException("Start FacePull streaming");
            phone.ReceiveTimeout = 0; phone.SendTimeout = 0; obs.NoDelay = true;
            var up = obs.GetStream().CopyToAsync(phone.GetStream()); var down = phone.GetStream().CopyToAsync(obs.GetStream());
            await Task.WhenAny(up, down); phone.Close(); obs.Close();
            try { await Task.WhenAll(up, down); } catch { }
        } catch {
            try { var response = Encoding.ASCII.GetBytes("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nRetry-After: 2\r\nConnection: close\r\n\r\n"); await obs.GetStream().WriteAsync(response, 0, response.Length); } catch { }
        } finally { if (phone != null) phone.Close(); obs.Close(); Slots.Release(); }
    }
    public static void Run(int localPort, int muxPort, string serial) {
        var listener = new TcpListener(IPAddress.Loopback, localPort); listener.Start();
        try { while (true) { var client = listener.AcceptTcpClient(); if (!Slots.Wait(0)) { client.Close(); continue; } Task.Run(() => Forward(client, muxPort, serial)); } }
        finally { listener.Stop(); }
    }
}

