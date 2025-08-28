//+------------------------------------------------------------------+
//| Deduplication utilities                                           |
//+------------------------------------------------------------------+

string g_DedupKeys[];
ulong  g_DedupTimes[];
int    g_DedupMaxSize = 256;

string BuildEventKey(string eventType, ulong ticket)
{
   return eventType + ":" + IntegerToString((long)ticket);
}

void PurgeOldDedupKeys()
{
   ulong now = GetTickCount64();
   int n = ArraySize(g_DedupKeys);
   if(n == 0)
      return;
   string newKeys[];
   ulong  newTimes[];
   ArrayResize(newKeys, 0);
   ArrayResize(newTimes, 0);
   for(int i=0;i<n;i++)
   {
      if(now - g_DedupTimes[i] <= (ulong)DedupWindowMs)
      {
         int idx = ArraySize(newKeys);
         ArrayResize(newKeys, idx+1);
         ArrayResize(newTimes, idx+1);
         newKeys[idx] = g_DedupKeys[i];
         newTimes[idx] = g_DedupTimes[i];
      }
   }
   g_DedupKeys = newKeys;
   g_DedupTimes = newTimes;
}

bool ShouldSendEvent(string eventType, ulong ticket)
{
   if(!EnableDedup)
      return true;
   if(eventType != "CLOSE")
      return true;
   PurgeOldDedupKeys();
   string key = BuildEventKey(eventType, ticket);
   int n = ArraySize(g_DedupKeys);
   for(int i=0;i<n;i++)
   {
      if(g_DedupKeys[i] == key)
      {
         if(ShowDebugInfo)
            Print("Дедуп: подавлен повтор события ", key);
         return false;
      }
   }
   if(n >= g_DedupMaxSize)
   {
      for(int j=1;j<n;j++)
      {
         g_DedupKeys[j-1] = g_DedupKeys[j];
         g_DedupTimes[j-1] = g_DedupTimes[j];
      }
      n--;
      ArrayResize(g_DedupKeys, n);
      ArrayResize(g_DedupTimes, n);
   }
   ArrayResize(g_DedupKeys, n+1);
   ArrayResize(g_DedupTimes, n+1);
   g_DedupKeys[n] = key;
   g_DedupTimes[n] = GetTickCount64();
   return true;
}


