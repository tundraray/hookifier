//+------------------------------------------------------------------+
//| Logger utilities - Модуль логирования                            |
//| Предоставляет функции для структурированного вывода сообщений    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Логирование информационного сообщения                            |
//| message - основной текст сообщения                               |
//| details - дополнительные детали (опционально)                    |
//| Формат: YYYY.MM.DD HH:MM:SS INFO: сообщение | детали            |
//+------------------------------------------------------------------+
void LogInfo(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " INFO: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

//+------------------------------------------------------------------+
//| Логирование сообщения об ошибке                                  |
//| message - описание ошибки                                        |
//| details - дополнительная информация об ошибке                    |
//| Формат: YYYY.MM.DD HH:MM:SS ERROR: ошибка | детали              |
//+------------------------------------------------------------------+
void LogError(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " ERROR: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

//+------------------------------------------------------------------+
//| Логирование предупреждения                                       |
//| message - текст предупреждения                                   |
//| details - дополнительная информация                              |
//| Формат: YYYY.MM.DD HH:MM:SS WARNING: предупреждение | детали    |
//+------------------------------------------------------------------+
void LogWarning(string message, string details = "")
{
   string logMessage = TimeToString(TimeCurrent()) + " WARNING: " + message;
   if(details != "")
      logMessage += " | " + details;
   
   Print(logMessage);
}

//+------------------------------------------------------------------+
//| Логирование отладочной информации                                |
//| message - отладочное сообщение                                   |
//| details - дополнительные отладочные данные                       |
//| Выводится только если включен ShowDebugInfo                      |
//| Формат: YYYY.MM.DD HH:MM:SS DEBUG: отладка | детали             |
//+------------------------------------------------------------------+
void LogDebug(string message, string details = "")
{
   if(!ShowDebugInfo)
      return;
   string logMessage = TimeToString(TimeCurrent()) + " DEBUG: " + message;
   if(details != "")
      logMessage += " | " + details;
   Print(logMessage);
}