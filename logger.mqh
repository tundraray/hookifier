//+------------------------------------------------------------------+
//| Logger utilities                                                  |
//+------------------------------------------------------------------+

void LogInfo(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " INFO: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

void LogError(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " ERROR: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

void LogWarning(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " WARNING: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

void LogDebug(string message, string details = "")
{
   if(!ShowDebugInfo)
      return;
   string logMessage = TimeToString(TimeCurrent()) + " DEBUG: " + message;
   if(details != "")
      logMessage += " | " + details;
   Print(logMessage);
}


