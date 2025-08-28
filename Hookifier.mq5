//+------------------------------------------------------------------+
//|                                                    Hookifier.mq5 |
//|                             Copyright 2025, Lavara Software Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Lavara Software Ltd."
#property link      "https://www.mql5.com"
#property version   "1.21"
#property description "Hookifier: Эксперт для отправки уведомлений о сделках на вебхук"

// Версии схемы и эксперта (держите в синхронизации с #property version)
#define JSON_SCHEMA_VERSION "1.0"
#define EA_VERSION          "1.21"

#include "logger.mqh"
#include "utils.mqh"
#include "dedup.mqh"
#include "webhook_client.mqh"
#include "json_builder.mqh"

//--- Входные параметры
input group   "=== Настройки вебхука ==="
input bool     SendToWebhook = true;    // Отправлять данные на вебхук
input string   WebhookURL = "https://n8n.unitup.space/webhook/80c71305-bf08-47fd-aaef-2977d3134a3d";          // URL вашего вебхука
input int      WebhookTimeout = 5000;    // Таймаут вебхука в миллисекундах

input group   "=== Дополнительные настройки ==="
input bool     ShowDebugInfo = true;    // Показывать отладочную информацию
input bool     TestWebhookOnInit = true; // Тестировать вебхук при запуске

input group   "=== Фильтры событий ==="
input bool     EnableOrderEvents = true;     // Отправлять события по ордерам
input bool     EnablePositionEvents = true;  // Отправлять события по позициям/сделкам
input bool     EnableSltpEvents = true;      // Отправлять события обновления SL/TP

input group   "=== Настройки надежности ==="
input int      MaxRetries = 3;          // Максимальное количество попыток
input int      RetryDelay = 1000;       // Задержка между попытками (мс)
input bool     EnableDedup = true;      // Включить подавление дубликатов событий
input int      DedupWindowMs = 600;     // Окно дедупликации (мс)



// Кэш и дедуп теперь в utils.mqh и dedup.mqh


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo("=== Webhook Expert Advisor инициализирован ===");
   
   // Инициализируем кэш
   InitializeCache();
   // Применим входные настройки (используются напрямую из input)
   
   LogInfo("Отправка на вебхук: " + (SendToWebhook ? "Включена" : "Отключена"));

   LogInfo("Таймаут вебхука: " + IntegerToString(WebhookTimeout) + " мс");
   
   if(SendToWebhook)
   {
      if(WebhookURL == "")
      {
         LogError("URL вебхука не указан!");
         return(INIT_PARAMETERS_INCORRECT);
      }
      
      LogInfo("URL вебхука: " + WebhookURL);
      CheckWebhookURL();
      
      // Тестируем вебхук при запуске (по настройке)
      if(TestWebhookOnInit)
         TestWebhookConnection();
   }
   
   // Инициализация больше не нужна с OnTradeTransaction
   
   // Таймер больше не нужен, так как используем OnTradeTransaction
   // EventSetMillisecondTimer(g_UpdateInterval);
   
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // EventKillTimer(); // Таймер больше не используется
   
   LogInfo("=== Webhook Expert Advisor остановлен ===");
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
   if(!SendToWebhook || WebhookURL == "")
      return;
   
   if(ShowDebugInfo)
      Print("=== Торговая транзакция: ", trans.type, " ===");
   
   // Обрабатываем различные типы транзакций
   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
         if(EnablePositionEvents)
            ProcessDealTransaction(trans);
         break;
         
      case TRADE_TRANSACTION_ORDER_ADD:
         if(EnableOrderEvents)
            ProcessOrderTransaction(trans);
         break;

      case TRADE_TRANSACTION_ORDER_UPDATE:
         if(EnableOrderEvents && EnableSltpEvents)
            ProcessOrderUpdateTransaction(trans, request);
         break;

         
      case TRADE_TRANSACTION_ORDER_DELETE:
         if(EnableOrderEvents)
            ProcessOrderDeleteTransaction(trans);
         break;
         
      case TRADE_TRANSACTION_POSITION:
         if(EnablePositionEvents && EnableSltpEvents)
            ProcessPositionTransaction(trans, request);
         break;
         
      case TRADE_TRANSACTION_REQUEST:
         ProcessRequestTransaction(trans, request);
         break;
         
      default:
         if(ShowDebugInfo)
            Print("Необработанный тип транзакции: ", trans.type);
         break;
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Таймер теперь используется только для периодических проверок
   // Основная логика перенесена в OnTradeTransaction
}

//+------------------------------------------------------------------+
//| Инициализация кэша                                               |
//+------------------------------------------------------------------+
void InitializeCache();

//+------------------------------------------------------------------+
//| Получение кэшированной информации об аккаунте                    |
//+------------------------------------------------------------------+
string GetCachedAccountInfo();

//+------------------------------------------------------------------+
//| Получение кэшированной информации о брокере                      |
//+------------------------------------------------------------------+
string GetCachedBrokerInfo();

//+------------------------------------------------------------------+
//| Получение сектора символа                                        |
//+------------------------------------------------------------------+
int GetSymbolSector(string symbol);



//+------------------------------------------------------------------+
//| Обработка транзакции сделки                                      |
//+------------------------------------------------------------------+
void ProcessDealTransaction(const MqlTradeTransaction& trans)
{
   if(ShowDebugInfo)
      Print("Обработка транзакции сделки: ", trans.deal);
   
   if(HistoryDealSelect(trans.deal))
   {
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      
      if(ShowDebugInfo)
         Print("  Тип сделки: ", dealType, ", Вход: ", dealEntry);
      
             // Открытие позиции (вход в позицию)
       if(dealEntry == DEAL_ENTRY_IN)
       {
          if(ShowDebugInfo)
             Print("  Открытие позиции: ", trans.deal);
          
          // Получаем тикет позиции из сделки
          ulong positionTicket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
          if(positionTicket != 0)
          {
             SendTradeNotification("OPEN", positionTicket);
          }
          else
          {
             LogError("Не удалось получить тикет позиции для сделки: " + IntegerToString(trans.deal));
          }
       }
      // Закрытие позиции (выход из позиции)
      else if(dealEntry == DEAL_ENTRY_OUT)
      {
         if(ShowDebugInfo)
            Print("  Закрытие позиции: ", trans.deal);
         SendTradeNotification("CLOSE", trans.deal);
      }
      // Частичное закрытие
      else if(dealEntry == DEAL_ENTRY_OUT_BY)
      {
         if(ShowDebugInfo)
            Print("  Частичное закрытие позиции: ", trans.deal);
         SendTradeNotification("PARTIAL_CLOSE", trans.deal);
      }
   }
}

//+------------------------------------------------------------------+
//| Обработка транзакции ордера                                      |
//+------------------------------------------------------------------+
void ProcessOrderTransaction(const MqlTradeTransaction& trans)
{
   if(ShowDebugInfo)
      Print("Обработка транзакции ордера: ", trans.order);
   
   if(OrderSelect(trans.order))
   {
      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      
      if(ShowDebugInfo)
         Print("  Создание отложенного ордера: ", trans.order, " типа: ", GetOrderTypeString(orderType));
      
      SendOrderNotification("PENDING", trans.order);
   }
}

//+------------------------------------------------------------------+
//| Обновление ордера                                                |
//+------------------------------------------------------------------+
void ProcessOrderUpdateTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   if(ShowDebugInfo)
      Print("Обновление ордера: ", trans.order);

   // Если это изменение SL/TP (или общая модификация с изменением SL/TP) — отправляем событие
   if(request.action == TRADE_ACTION_SLTP || request.action == TRADE_ACTION_MODIFY)
   {
      // Отправляем только для активных (неисторических) ордеров в состоянии PLACED
      if(OrderSelect(trans.order))
      {
         ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         if(orderState == ORDER_STATE_PLACED)
            SendOrderSltpUpdateNotification(trans.order);
      }
      return;
   }
}

//+------------------------------------------------------------------+
//| Обработка удаления ордера                                        |
//+------------------------------------------------------------------+
void ProcessOrderDeleteTransaction(const MqlTradeTransaction& trans)
{
   if(ShowDebugInfo)
      Print("Обработка удаления ордера: ", trans.order);
   
   // Проверяем состояние ордера в истории
   if(HistoryOrderSelect(trans.order))
   {
      ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE);
      
      if(ShowDebugInfo)
         Print("  Состояние удаленного ордера: ", orderState);
      
      if(orderState == ORDER_STATE_FILLED)
      {
         if(ShowDebugInfo)
            Print("  Ордер исполнен: ", trans.order);
         // Получим position_id из истории ордера
         ulong posId = HistoryOrderGetInteger(trans.order, ORDER_POSITION_ID);
         SendOrderNotification("ACTIVATED", trans.order, posId);
         // Ордер исполнен — кеш не используется
      }
      else if(orderState == ORDER_STATE_CANCELED)
      {
         if(ShowDebugInfo)
            Print("  Ордер отменен: ", trans.order);
         SendOrderNotification("CANCELED", trans.order);
         
      }
      else if(orderState == ORDER_STATE_PARTIAL)
      {
         if(ShowDebugInfo)
            Print("  Ордер частично исполнен: ", trans.order);
         SendOrderNotification("PARTIAL", trans.order);
         // PARTIAL в истории: отложка частично исполнена
      }
      else if(orderState == ORDER_STATE_REJECTED)
      {
         if(ShowDebugInfo)
            Print("  Ордер отклонен: ", trans.order);
         SendOrderNotification("REJECTED", trans.order);
         
      }
      else if(orderState == ORDER_STATE_EXPIRED)
      {
         if(ShowDebugInfo)
            Print("  Ордер истек: ", trans.order);
         SendOrderNotification("EXPIRED", trans.order);
         
      }
      else
      {
         if(ShowDebugInfo)
            Print("  Ордер удален: ", trans.order);
         SendOrderNotification("DELETE", trans.order);
         
      }
   }
}

//+------------------------------------------------------------------+
//| Обработка транзакции позиции                                     |
//+------------------------------------------------------------------+
void ProcessPositionTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   if(ShowDebugInfo)
      Print("Изменение позиции: ", trans.position);
   
   if(PositionSelectByTicket(trans.position))
   {
      if(ShowDebugInfo)
         Print("  Изменение позиции: ", trans.position);

      // В рамках обновлений позиции отправим событие изменения SL/TP
      SendPositionSltpUpdateNotification(trans.position);
   }
}

//+------------------------------------------------------------------+
//| Обработка транзакции запроса                                     |
//+------------------------------------------------------------------+
void ProcessRequestTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   if(ShowDebugInfo)
      Print("Обработка транзакции запроса: ", trans.type);
   
   // Обрабатываем торговые запросы
   if(ShowDebugInfo)
      Print("  Тип запроса: ", trans.type);
}




//+------------------------------------------------------------------+
//| Поиск сделки закрытия для позиции                                |
//+------------------------------------------------------------------+
ulong FindCloseDealForPosition(ulong positionTicket)
{
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      
      if(HistoryDealSelect(dealTicket))
      {
         ulong dealPositionID = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         
         if(dealPositionID == positionTicket && dealEntry == DEAL_ENTRY_OUT)
         {
            return dealTicket;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Валидация торговых данных                                        |
//+------------------------------------------------------------------+
bool ValidateTradeData(ulong ticket, string eventType)
{
   if(ticket == 0) 
   {
      LogError("Недопустимый тикет: " + IntegerToString(ticket));
      return false;
   }
   
   if(eventType == "OPEN")
   {
      if(!PositionSelectByTicket(ticket))
      {
         LogError("Позиция не найдена: " + IntegerToString(ticket));
         return false;
      }
   }
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
   {
      if(!HistoryDealSelect(ticket))
      {
         LogError("Сделка не найдена: " + IntegerToString(ticket));
         return false;
      }
   }
   else if(eventType == "PENDING")
   {
      if(!OrderSelect(ticket))
      {
         LogError("Ордер не найден: " + IntegerToString(ticket));
         return false;
      }
   }
   else
   {
      if(!HistoryOrderSelect(ticket))
      {
         LogError("Исторический ордер не найден: " + IntegerToString(ticket));
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Отправка уведомления о сделке                                    |
//+------------------------------------------------------------------+
void SendTradeNotification(string tradeType, ulong ticket)
{
   if(ShowDebugInfo)
      Print("Отправка уведомления: ", tradeType, " тикет: ", ticket);
   
   // Дедупликация
   if(!ShouldSendEvent(tradeType, ticket))
      return;

   // Валидируем данные перед отправкой
   if(!ValidateTradeData(ticket, tradeType))
   {
      LogError("Данные не прошли валидацию для типа: " + tradeType);
      return;
   }
   
   string json = CreateStandardJSON(tradeType, ticket);
   
   if(ShowDebugInfo)
      Print("JSON готов для отправки: ", json);
   
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Отправка уведомления об отложенном ордере                         |
//+------------------------------------------------------------------+
void SendOrderNotification(string orderType, ulong ticket, ulong positionTicket = 0)
{
   if(ShowDebugInfo)
      Print("Отправка уведомления об ордере: ", orderType, " тикет: ", ticket);
   
   // Валидируем данные перед отправкой
   if(!ValidateTradeData(ticket, orderType))
   {
      LogError("Данные не прошли валидацию для типа: " + orderType);
      return;
   }
   
   string json = CreateStandardJSON(orderType, ticket, positionTicket);
   
   if(ShowDebugInfo)
      Print("JSON готов для отправки: ", json);
   
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Отправка события обновления SL/TP позиции                         |
//+------------------------------------------------------------------+
void SendPositionSltpUpdateNotification(ulong positionTicket)
{
   if(!SendToWebhook || WebhookURL == "")
      return;

   if(!EnableSltpEvents || !EnablePositionEvents)
      return;

   // Валидация: позиция должна существовать
   if(!PositionSelectByTicket(positionTicket))
      return;

   string json = CreateStandardJSON("POSITION_SLTP_UPDATE", positionTicket);
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Отправка события обновления SL/TP ордера                          |
//+------------------------------------------------------------------+
void SendOrderSltpUpdateNotification(ulong orderTicket)
{
   if(!SendToWebhook || WebhookURL == "")
      return;

   if(!EnableSltpEvents || !EnableOrderEvents)
      return;

   // Валидация: отправляем только для активных ордеров (не для исторических)
   if(!OrderSelect(orderTicket))
      return;

   ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
   if(orderState != ORDER_STATE_PLACED)
      return;

   string json = CreateStandardJSON("ORDER_SLTP_UPDATE", orderTicket);
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Создание базового JSON для всех событий                           |
//+------------------------------------------------------------------+
string CreateBaseJSON(string eventType, ulong ticket);

//+------------------------------------------------------------------+
//| Дедупликация: хэш события                                         |
//+------------------------------------------------------------------+
string BuildEventKey(string eventType, ulong ticket);

//+------------------------------------------------------------------+
//| Дедупликация: очистка устаревших ключей                           |
//+------------------------------------------------------------------+
void PurgeOldDedupKeys();

//+------------------------------------------------------------------+
//| Дедупликация: проверка и запись события                           |
//+------------------------------------------------------------------+
bool ShouldSendEvent(string eventType, ulong ticket);

//+------------------------------------------------------------------+
//| Создание JSON для позиции                                         |
//+------------------------------------------------------------------+
string CreatePositionJSON(ulong ticket);

//+------------------------------------------------------------------+
//| Создание JSON для сделки                                          |
//+------------------------------------------------------------------+
string CreateDealJSON(ulong ticket, string eventType);

//+------------------------------------------------------------------+
//| Создание JSON для ордера                                          |
//+------------------------------------------------------------------+
string CreateOrderJSON(ulong ticket, bool isHistorical = false);

//+------------------------------------------------------------------+
//| JSON для обновления SL/TP ордера                                 |
//+------------------------------------------------------------------+
string CreateOrderSltpUpdateJSON(ulong ticket);

//+------------------------------------------------------------------+
//| JSON для обновления SL/TP позиции                                 |
//+------------------------------------------------------------------+
string CreatePositionSltpUpdateJSON(ulong positionTicket);

//+------------------------------------------------------------------+
//| Создание JSON для информации о позиции                            |
//+------------------------------------------------------------------+
string CreatePositionInfoJSON(ulong positionTicket);

//+------------------------------------------------------------------+
//| Создание стандартизированного JSON для всех типов событий         |
//+------------------------------------------------------------------+
string CreateStandardJSON(string eventType, ulong ticket, ulong positionTicket = 0);



//+------------------------------------------------------------------+
//| Получение строкового представления типа ордера                    |
//+------------------------------------------------------------------+
string GetOrderTypeString(ENUM_ORDER_TYPE orderType)
{
   switch(orderType)
   {
      case ORDER_TYPE_BUY_LIMIT:     return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:    return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:      return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP:     return "SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT: return "BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT: return "SELL_STOP_LIMIT";
      default:                       return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Отправка JSON на вебхук с повторными попытками                   |
//+------------------------------------------------------------------+
bool SendWebhookJSONWithRetry(string jsonData);

//+------------------------------------------------------------------+
//| Универсальная функция отправки JSON на вебхук                    |
//+------------------------------------------------------------------+
bool SendWebhookJSON(string jsonData);



//+------------------------------------------------------------------+
//| Принудительная проверка всех закрытых сделок                     |
//+------------------------------------------------------------------+
void ForceCheckClosedTrades()
{
   if(ShowDebugInfo)
      LogInfo("Принудительная проверка закрытых сделок");
   
   // Реализация проверки закрытых сделок
   // Можно добавить логику для проверки всех закрытых сделок
}


//+------------------------------------------------------------------+
//| Структурированное логирование                                    |
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

//+------------------------------------------------------------------+
//| Показать текущие настройки                                       |
//+------------------------------------------------------------------+
void ShowCurrentSettings()
{
   LogInfo("=== ТЕКУЩИЕ НАСТРОЙКИ ===");
   LogInfo("SendToWebhook: " + (SendToWebhook ? "Включено" : "Отключено"));
   LogInfo("WebhookURL: " + WebhookURL);
   LogInfo("WebhookTimeout: " + IntegerToString(WebhookTimeout) + " мс");
   LogInfo("ShowDebugInfo: " + (ShowDebugInfo ? "Включено" : "Отключено"));
   LogInfo("MaxRetries: " + IntegerToString(MaxRetries));
   LogInfo("RetryDelay: " + IntegerToString(RetryDelay) + " мс");
   LogInfo("EnableDedup: " + (EnableDedup ? "Включено" : "Отключено"));
   LogInfo("DedupWindowMs: " + IntegerToString(DedupWindowMs) + " мс");
   LogInfo("=========================");
}

//+------------------------------------------------------------------+
//| Проверка валидности JSON                                         |
//+------------------------------------------------------------------+
bool IsValidJSON(string jsonData)
{
   // Проверяем базовую структуру JSON
   if(StringLen(jsonData) == 0)
      return false;
      
   // Проверяем, что JSON начинается с { и заканчивается на }
   if(StringGetCharacter(jsonData, 0) != '{')
      return false;
      
   if(StringGetCharacter(jsonData, StringLen(jsonData) - 1) != '}')
      return false;
      
   // Проверяем на наличие лишних символов в конце
   string trimmed = jsonData;
   StringTrimRight(trimmed);
   if(StringLen(trimmed) != StringLen(jsonData))
   {
      LogWarning("⚠ Обнаружены лишние символы в конце JSON");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Экранирование специальных символов для JSON                      |
//+------------------------------------------------------------------+
string EscapeJSONString(string text)
{
   string result = "";
   int len = StringLen(text);
   
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(text, i);
      
      switch(ch)
      {
         case '"':  result += "\\\""; break;
         case '\\': result += "\\\\"; break;
         case 8:    result += "\\b";  break;  // \b
         case 12:   result += "\\f";  break;  // \f
         case 10:   result += "\\n";  break;  // \n
         case 13:   result += "\\r";  break;  // \r
         case 9:    result += "\\t";  break;  // \t
         default:
                         if(ch < 32 || ch > 126)
             {
                // Экранируем Unicode символы
                result += "\\u" + StringFormat("%04X", ch);
             }
             else
             {
                result += ShortToString(ch);
             }
            break;
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Форматирование времени в ISO-8601 (UTC, с Z)                      |
//+------------------------------------------------------------------+
string ToIso8601(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   // Используем локальное время терминала; при желании можно TimeGMT()
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

//+------------------------------------------------------------------+
//| Получение точности цены для символа                               |
//+------------------------------------------------------------------+
int GetDigitsForSymbol(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 5; // запасной вариант
   return digits;
}



//+------------------------------------------------------------------+
//| Проверка URL вебхука                                             |
//+------------------------------------------------------------------+
void CheckWebhookURL();

//+------------------------------------------------------------------+
//| Тестирование соединения с вебхуком                               |
//+------------------------------------------------------------------+
void TestWebhookConnection();
