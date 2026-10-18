using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace WowAuto.Threading {
    public sealed class QueueTimings {
        public int OperatorIdleMs=25,CommandReceiveMs=10,ReplyCheckMs=25,WaitCheckMs=25,DetectorWaitMs=20,UiRefreshMs=25;
        public int ForegroundSettleMs=200,ForegroundRetryMs=100,ForegroundTimeoutMs=800,RotationFocusRetryMs=500,RotationFocusTimeoutMs=5000,FocusRetryMs=30000;
        public int KeyPressMs=30,ChatKeyPressMs=50,CommandIntervalMs=500,ReelHoldMs=100,ItemHoldMs=3000,InteractionHoldMs=3500;
        public int ClickMinMs=100,ClickMaxMs=250,ClickGuardMs=1000,CaptureRetryMs=100;
        public QueueTimings Copy() {return (QueueTimings)MemberwiseClone();}
    }
    public sealed class Command {
        public string Kind, Json;
        public long Version;
    }
    public sealed class Endpoint {
        public string Key, Path, Flavor;
        public int Pid;
        public long StartTicks;
        long version;
        Command configuration;
        public volatile bool Closed;
        public readonly BlockingCollection<Command> Commands=new BlockingCollection<Command>();
        public long Version { get {return Interlocked.Read(ref version);} }
        public long Send(string kind,string json) {
            long next=Interlocked.Increment(ref version);
            if(!Closed) Commands.Add(new Command {Kind=kind,Json=json,Version=next});
            return next;
        }
        public bool Current(long expected) {return !Closed && Version==expected;}
        public Command Configuration {get {return Interlocked.CompareExchange(ref configuration,null,null);}}
        public void Notify(string kind,string json) {
            if(Closed) return;
            var command=new Command {Kind=kind,Json=json,Version=Version};
            if(kind=="Configure") Interlocked.Exchange(ref configuration,command);else Commands.Add(command);
        }
        public void Close() {Closed=true;Interlocked.Increment(ref version);}
        public void Finish() {Closed=true;} // Keep the final stopped notice's version readable by the UI.
        public Command Receive(int timeout) {Command command;return Commands.TryTake(out command,timeout)?command:null;}
    }
    public sealed class Operation {
        public QueueTimings Timing=new QueueTimings();
        public Endpoint Owner;
        public long Version, Sequence, Due, ReadyAt, FocusUntil, NextActivateAt;
        public string Kind, Domain, Json, Result, Error;
        public int Priority;
        public bool Success, Executed;
        public readonly ManualResetEventSlim Done=new ManualResetEventSlim(false);
        public bool Current {get {return Owner.Current(Version);}}
        public void Complete(bool success,bool executed,string result,string error) {
            Success=success;Executed=executed;Result=result;Error=error;Done.Set();
        }
    }
    public sealed class Notice {
        public string Key, Kind, Json;
        public long Version;
        public int ThreadId;
    }
    // Batch barriers coordinate workers without giving a worker another process's state.
    public sealed class RotationBatch {
        readonly object gate=new object();
        readonly Dictionary<string,int> members=new Dictionary<string,int>();
        public readonly string Id=Guid.NewGuid().ToString("N");
        public RotationBatch(string[] keys) {foreach(string key in keys) members[key]=0;}
        public void Mark(string key,int flag) {lock(gate) {if(members.ContainsKey(key)) members[key]|=flag;}}
        public void Clear(string key,int flag) {lock(gate) {if(members.ContainsKey(key)) members[key]&=~flag;}}
        public void Drop(string key) {Mark(key,15);}
        public bool All(int flag) {lock(gate) return members.Values.All(value=>(value&flag)==flag);}
        public bool Contains(string key) {lock(gate) return members.ContainsKey(key);}
    }
    public sealed class Hub {
        readonly object requestsGate=new object(), logGate=new object();
        readonly List<Operation> requests=new List<Operation>();
        readonly ConcurrentQueue<Notice> notices=new ConcurrentQueue<Notice>();
        readonly ConcurrentDictionary<string,Endpoint> endpoints=new ConcurrentDictionary<string,Endpoint>();
        readonly Stopwatch clock=Stopwatch.StartNew();
        readonly string logPath,infoPath;
        readonly Encoding utf8=new UTF8Encoding(false);
        long sequence;
        QueueTimings timing=new QueueTimings();
        public QueueTimings Timing {get {return Interlocked.CompareExchange(ref timing,null,null);}}
        public void ConfigureTiming(QueueTimings value) {if(value==null) throw new ArgumentNullException("value");Interlocked.Exchange(ref timing,value.Copy());Wake.Set();}
        public volatile bool Closing, Paused;
        public bool Simulation;
        public volatile RotationBatch Batch;
        public Operation Focus;
        public int LogMaxSizeMB;
        public volatile int ActiveTasks;
        public readonly AutoResetEvent Wake=new AutoResetEvent(false);
        public Hub(string directory,int limit) {
            Directory.CreateDirectory(directory);logPath=System.IO.Path.Combine(directory,"wowAuto.log");
            infoPath=System.IO.Path.Combine(directory,"info.log");LogMaxSizeMB=limit;
        }
        public long Now {get {return clock.ElapsedMilliseconds;}}
        public Endpoint Register(string key,int pid,long ticks,string path,string flavor) {
            var endpoint=new Endpoint {Key=key,Pid=pid,StartTicks=ticks,Path=path,Flavor=flavor};
            if(!endpoints.TryAdd(key,endpoint)) throw new InvalidOperationException("Duplicate process worker");
            return endpoint;
        }
        public void Remove(string key) {Endpoint endpoint;if(endpoints.TryRemove(key,out endpoint)) endpoint.Close();Wake.Set();}
        public void Publish(Endpoint endpoint,long version,string kind,string json) {
            notices.Enqueue(new Notice {Key=endpoint.Key,Version=version,Kind=kind,Json=json,ThreadId=Thread.CurrentThread.ManagedThreadId});
        }
        public Notice NextNotice() {Notice notice;return notices.TryDequeue(out notice)?notice:null;}
        public Operation Request(Endpoint owner,long version,string kind,string domain,int priority,string json) {
            return Request(owner,version,kind,domain,priority,json,Timing);
        }
        public Operation Request(Endpoint owner,long version,string kind,string domain,int priority,string json,QueueTimings requestedTiming) {
            var operation=new Operation {Owner=owner,Version=version,Kind=kind,Domain=domain,Priority=priority,Json=json,
                Sequence=Interlocked.Increment(ref sequence),Due=Now,Timing=(requestedTiming??Timing).Copy()};
            lock(requestsGate) {
                if(Closing || !operation.Current) operation.Complete(false,false,null,"cancelled");
                else requests.Add(operation);
            }
            Wake.Set();return operation;
        }
        public Operation NextOperation() {
            lock(requestsGate) {
                for(int i=requests.Count-1;i>=0;i--) if(!requests[i].Current) {
                    requests[i].Complete(false,false,null,"cancelled");requests.RemoveAt(i);
                }
                if(Closing || Paused) return null;
                bool rotating=Batch!=null && !Batch.All(8);
                var next=requests.Where(r=>r.Due<=Now && (!rotating || r.Domain=="Rotation" || r.Domain=="Process" || r.Kind=="Capture.Restore"))
                    .OrderBy(r=>r.Priority).ThenBy(r=>r.Due).ThenBy(r=>r.Sequence).FirstOrDefault();
                if(Focus!=null && (!Focus.Current || !requests.Contains(Focus))) Focus=null;
                if(Focus!=null) {
                    if(next!=null && (next.Priority<Focus.Priority || next.Kind=="Capture.Restore")) {Focus.ReadyAt=0;Focus=null;}
                    else next=Focus.Due<=Now?Focus:null;
                }
                if(next!=null) requests.Remove(next);
                return next;
            }
        }
        public void Requeue(Operation operation,int delay) {
            lock(requestsGate) {
                if(operation.Current && !Closing) {operation.Due=Now+delay;requests.Add(operation);}
                else operation.Complete(false,false,null,"cancelled");
            }
        }
        public void Close() {
            Closing=true;Focus=null;foreach(var endpoint in endpoints.Values) endpoint.Close();
            lock(requestsGate) {foreach(var request in requests) request.Complete(false,false,null,"cancelled");requests.Clear();}
            Wake.Set();
        }
        static string Quote(string text) {
            var result=new StringBuilder("\"");
            foreach(char c in text??"") {
                if(c=='"' || c=='\\') result.Append('\\').Append(c);
                else if(c=='\n') result.Append("\\n");else if(c=='\r') result.Append("\\r");
                else if(c<32) result.Append("\\u").Append(((int)c).ToString("x4"));else result.Append(c);
            }
            return result.Append('"').ToString();
        }
        public void Log(Endpoint endpoint,long version,string kind,string message) {
            string line="{\"Time\":"+Quote(DateTimeOffset.Now.ToString("o"))+",\"Pid\":"+(endpoint==null?"null":endpoint.Pid.ToString())+
                ",\"Kind\":"+Quote(kind)+",\"ThreadId\":"+Thread.CurrentThread.ManagedThreadId+",\"Message\":"+Quote(message)+"}\n";
            lock(logGate) {Append(utf8.GetBytes(line));}
            if(endpoint!=null && (kind=="status" || kind=="error")) Publish(endpoint,version,"status",message);
        }
        void Append(byte[] bytes) {
            long info=File.Exists(infoPath)?new FileInfo(infoPath).Length:0;
            long budget=(long)LogMaxSizeMB*1024*1024-info;
            if(bytes.Length>budget || budget<=0) throw new IOException("Log size limit is too small for the current info snapshot");
            long length=File.Exists(logPath)?new FileInfo(logPath).Length:0;
            if(length+bytes.Length>budget) {
                string temporary=logPath+"."+Guid.NewGuid().ToString("N")+".tmp";
                try {
                    using(var target=File.Create(temporary)) using(var source=File.Open(logPath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
                        long keep=(long)((budget-bytes.Length)*0.9);source.Position=Math.Max(0,length-keep);
                        if(source.Position>0) while(source.Position<length && source.ReadByte()!=10) {}
                        source.CopyTo(target);target.Write(bytes,0,bytes.Length);
                    }
                    File.Replace(temporary,logPath,null);
                } finally {if(File.Exists(temporary)) File.Delete(temporary);}
            } else using(var target=File.Open(logPath,FileMode.Append,FileAccess.Write,FileShare.Read)) target.Write(bytes,0,bytes.Length);
        }
        public void WriteInfo(string json) {
            lock(logGate) {
                byte[] bytes=utf8.GetBytes(json+"\n");
                if(bytes.Length>=(long)LogMaxSizeMB*1024*1024) throw new IOException("Info snapshot exceeds the log limit");
                string temporary=infoPath+"."+Guid.NewGuid().ToString("N")+".tmp";
                try {File.WriteAllBytes(temporary,bytes);if(File.Exists(infoPath)) File.Replace(temporary,infoPath,null);else File.Move(temporary,infoPath);}
                finally {if(File.Exists(temporary)) File.Delete(temporary);}
                Append(new byte[0]);
            }
        }
    }
}
