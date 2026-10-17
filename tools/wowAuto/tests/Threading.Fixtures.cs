using System;
using System.Threading;
using WowAuto.Threading;
public static class ThreadingChecks {
    public static void Logs(Hub hub,Endpoint endpoint) {
        var threads=new Thread[4];
        for(int i=0;i<threads.Length;i++) {threads[i]=new Thread(()=>{for(int n=0;n<300;n++) hub.Log(endpoint,endpoint.Version,"test",new string('x',900)+n);});threads[i].Start();}
        foreach(var thread in threads) thread.Join();
    }
    public static string ReadIsolation() {
        var ready=new ManualResetEventSlim(false);var read=new ManualResetEventSlim(false);string failure=null;
        WowAutoFight.Native.FrameReader=(pid,ticks,path)=>{throw new InvalidOperationException(pid==1?"pending-A":"error-B");};
        WowAutoFight.Native.CapturePending=error=>error.Message=="pending-A";
        var first=new Thread(()=>{WowAutoFight.Native.Read(new WowAutoFight.Client {ProcessId=1});ready.Set();read.Wait();if(!WowAutoFight.Native.LastReadPending || WowAutoFight.Native.LastReadError!="pending-A") failure="A overwritten";});
        var second=new Thread(()=>{ready.Wait();WowAutoFight.Native.Read(new WowAutoFight.Client {ProcessId=2});if(WowAutoFight.Native.LastReadPending || WowAutoFight.Native.LastReadError!="error-B") failure="B overwritten";read.Set();});
        first.Start();second.Start();first.Join();second.Join();return failure;
    }
}
