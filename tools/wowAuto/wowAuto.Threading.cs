using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace WowAuto.Threading {
    // Callers enqueue immutable values; only this thread touches the two log files.
    public sealed class LogWriter {
        sealed class Entry {
            public string Kind,Message,Json,Time;
            public int? Pid;
            public int SourceThreadId,Limit;
            public ManualResetEventSlim Barrier;
        }
        readonly object queueGate=new object();
        readonly BlockingCollection<Entry> queue=new BlockingCollection<Entry>(4096);
        readonly ManualResetEventSlim ready=new ManualResetEventSlim(false);
        readonly Thread thread;
        readonly string directory,logPath,infoPath;
        readonly Encoding utf8=new UTF8Encoding(false);
        string lastError="",startupError="",pendingError;
        bool accepting=true;
        int requestedLimit,limit,threadId;
        public LogWriter(string directory,int maximum) {
            ValidateLimit(maximum);this.directory=directory;requestedLimit=limit=maximum;
            logPath=Path.Combine(directory,"wowAuto.log");infoPath=Path.Combine(directory,"info.log");
            thread=new Thread(Run) {IsBackground=true,Name="wowAuto.LogWriter"};thread.Start();
            if(!ready.Wait(5000)) {Close(0);throw new IOException("Log thread initialization timed out");}
            if(startupError.Length>0) {Close(5000);throw new IOException(startupError);}
        }
        public int ThreadId {get {return Volatile.Read(ref threadId);}}
        public bool IsAlive {get {return thread.IsAlive;}}
        public string LastError {get {return Volatile.Read(ref lastError);}}
        public string TakeError() {return Interlocked.Exchange(ref pendingError,null);}
        public int MaxSizeMB {get {return Volatile.Read(ref requestedLimit);} set {
            ValidateLimit(value);
            lock(queueGate) {Enqueue(new Entry {Kind="limit",Limit=value});Volatile.Write(ref requestedLimit,value);}
        }}
        static void ValidateLimit(int value) {if(value<1 || value>1024) throw new ArgumentOutOfRangeException("maximum");}
        void Enqueue(Entry entry) {
            lock(queueGate) {
                if(!accepting) throw new InvalidOperationException("Log thread has stopped accepting messages");
                if(!queue.TryAdd(entry)) throw new IOException("Log queue is full; message was not accepted");
            }
        }
        public void Log(int? pid,string kind,string message) {
            Enqueue(new Entry {Kind="log",Pid=pid,Json=kind,Message=message,
                Time=DateTimeOffset.Now.ToString("o"),SourceThreadId=Thread.CurrentThread.ManagedThreadId});
        }
        public void WriteInfo(string json) {Enqueue(new Entry {Kind="info",Json=json});}
        // Barriers are used by offline tests and shutdown, never by a UI refresh.
        public bool Flush(int timeout) {
            var barrier=new ManualResetEventSlim(false);
            Enqueue(new Entry {Kind="barrier",Barrier=barrier});return barrier.Wait(timeout);
        }
        public bool Close(int timeout) {
            lock(queueGate) {if(accepting) {accepting=false;queue.CompleteAdding();}}
            return thread.Join(timeout);
        }
        void Run() {
            Volatile.Write(ref threadId,Thread.CurrentThread.ManagedThreadId);
            try {
                Directory.CreateDirectory(directory);
                File.WriteAllText(logPath,"",utf8);File.WriteAllText(infoPath,"",utf8);
            } catch(Exception error) {startupError=error.Message;Volatile.Write(ref lastError,error.Message);return;}
            finally {ready.Set();}
            foreach(var entry in queue.GetConsumingEnumerable()) {
                try {
                    if(entry.Kind=="barrier") {entry.Barrier.Set();continue;}
                    if(entry.Kind=="info") WriteInfoFile(entry.Json);
                    else if(entry.Kind=="limit") {limit=entry.Limit;Append(new byte[0]);}
                    else {
                        string line="{\"Time\":"+Quote(entry.Time)+",\"Pid\":"+(entry.Pid.HasValue?entry.Pid.Value.ToString():"null")+
                            ",\"Kind\":"+Quote(entry.Json)+",\"ThreadId\":"+entry.SourceThreadId+",\"WriterThreadId\":"+ThreadId+
                            ",\"Message\":"+Quote(entry.Message)+"}\n";
                        Append(utf8.GetBytes(line));
                    }
                    Volatile.Write(ref lastError,"");
                } catch(Exception error) {Volatile.Write(ref lastError,error.Message);Interlocked.Exchange(ref pendingError,error.Message);}
            }
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
        void Append(byte[] bytes) {
            long info=File.Exists(infoPath)?new FileInfo(infoPath).Length:0;
            long budget=(long)limit*1024*1024-info;
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
        void WriteInfoFile(string json) {
            byte[] bytes=utf8.GetBytes(json+"\n");
            if(bytes.Length>=(long)limit*1024*1024) throw new IOException("Info snapshot exceeds the log limit");
            string temporary=infoPath+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {File.WriteAllBytes(temporary,bytes);File.Replace(temporary,infoPath,null);}
            finally {if(File.Exists(temporary)) File.Delete(temporary);}
            Append(new byte[0]);
        }
    }
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
        public bool CloseRequested, KillRequested;
        public long CloseDeadline, KillDeadline;
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
        readonly object requestsGate=new object();
        readonly List<Operation> requests=new List<Operation>();
        readonly ConcurrentQueue<Notice> notices=new ConcurrentQueue<Notice>();
        readonly ConcurrentDictionary<string,Endpoint> endpoints=new ConcurrentDictionary<string,Endpoint>();
        readonly Stopwatch clock=Stopwatch.StartNew();
        public readonly LogWriter Logger;
        int operatorThreadId;
        public int OperatorThreadId {get {return Volatile.Read(ref operatorThreadId);}}
        public void BindOperator() {
            int current=Thread.CurrentThread.ManagedThreadId;
            int previous=Interlocked.CompareExchange(ref operatorThreadId,current,0);
            if(previous!=0 && previous!=current) throw new InvalidOperationException("An operator thread is already assigned");
        }
        public void AssertOperatorThread() {
            if(OperatorThreadId!=Thread.CurrentThread.ManagedThreadId) throw new InvalidOperationException("Game input belongs to the operator thread");
        }
        long sequence;
        QueueTimings timing=new QueueTimings();
        public QueueTimings Timing {get {return Interlocked.CompareExchange(ref timing,null,null);}}
        public void ConfigureTiming(QueueTimings value) {if(value==null) throw new ArgumentNullException("value");Interlocked.Exchange(ref timing,value.Copy());Wake.Set();}
        public volatile bool Closing, Paused;
        public bool Simulation;
        public volatile RotationBatch Batch;
        public Operation Focus;
        public int LogMaxSizeMB {get {return Logger.MaxSizeMB;} set {Logger.MaxSizeMB=value;}}
        public volatile int ActiveTasks;
        public readonly AutoResetEvent Wake=new AutoResetEvent(false);
        public Hub(string directory,int limit):this(new LogWriter(directory,limit)) {}
        public Hub(LogWriter logger) {if(logger==null) throw new ArgumentNullException("logger");Logger=logger;}
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
        // A native C# delegate is safe on the audio thread; PowerShell callbacks
        // would require a runspace there. Queue insertion wakes Endpoint.Receive.
        public Action<long> CreateAudioNotifier(Endpoint endpoint,long version) {
            if(endpoint==null) throw new ArgumentNullException("endpoint");
            return session=>{
                if(session<=0 || Closing || !endpoint.Current(version)) return;
                string json=String.Format(System.Globalization.CultureInfo.InvariantCulture,
                    "{{\"Session\":{0},\"MatchedAt\":{1}}}",session,Now);
                endpoint.Commands.Add(new Command {Kind="Audio.Bite",Version=version,Json=json});
            };
        }
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
            if(OperatorThreadId!=0) AssertOperatorThread();
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
        public void Log(Endpoint endpoint,long version,string kind,string message) {
            Logger.Log(endpoint==null?(int?)null:endpoint.Pid,kind,message);
            if(endpoint!=null && (kind=="status" || kind=="error")) Publish(endpoint,version,"status",message);
        }
        public void WriteInfo(string json) {Logger.WriteInfo(json);}
    }
}
