//+------------------------------------------------------------------+
//|                                                      Webhook.mq5 |
//|                             Copyright 2025, Lavara Software Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Lavara Software Ltd."
#property link      "https://www.mql5.com"
#property version   "1.21"
#property description "Эксперт для отправки уведомлений о сделках на вебхук"

//--- Входные параметры
input group   "=== Настройки вебхука ==="
input bool     SendToWebhook = true;    // Отправлять данные на вебхук
input string   WebhookURL = "https://n8n.unitup.space/webhook/80c71305-bf08-47fd-aaef-2977d3134a3d";          // URL вашего вебхука
input int      WebhookTimeout = 5000;    // Таймаут вебхука в миллисекундах

input group   "=== Дополнительные настройки ==="
input bool     ShowDebugInfo = true;    // Показывать отладочную информацию

input group   "=== Настройки надежности ==="
input int      MaxRetries = 3;          // Максимальное количество попыток
input int      RetryDelay = 1000;       // Задержка между попытками (мс)
input bool     EnableDedup = true;      // Включить подавление дубликатов событий
input int      DedupWindowMs = 600;     // Окно дедупликации (мс)

//--- Глобальные переменные
// Переменные для хранения настроек (изменяемые)
bool g_SendToWebhook = false;
string g_WebhookURL = "";
int g_WebhookTimeout = 5000;
bool g_ShowDebugInfo = false;
bool g_EnableDedup = true;
int  g_DedupWindowMs = 600;


// Кэш для часто используемых данных
string cachedAccountInfo = "";
string cachedBrokerInfo = "";

// Дедупликация событий (in-memory)
string g_DedupKeys[];
ulong  g_DedupTimes[];
int    g_DedupMaxSize = 256;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo("=== Webhook Expert Advisor инициализирован ===");
   
   // Настройки всегда берём из input
   g_WebhookURL = WebhookURL;
   g_WebhookTimeout = WebhookTimeout;
   g_SendToWebhook = SendToWebhook;
   g_ShowDebugInfo = ShowDebugInfo;
   
   // Инициализируем кэш
   InitializeCache();
   // Применим входные настройки для дедупликации
   g_EnableDedup = EnableDedup;
   g_DedupWindowMs = DedupWindowMs;
   
   LogInfo("Отправка на вебхук: " + (g_SendToWebhook ? "Включена" : "Отключена"));

   LogInfo("Таймаут вебхука: " + IntegerToString(g_WebhookTimeout) + " мс");
   
   if(g_SendToWebhook)
   {
      if(g_WebhookURL == "")
      {
         LogError("URL вебхука не указан!");
         return(INIT_PARAMETERS_INCORRECT);
      }
      
      LogInfo("URL вебхука: " + g_WebhookURL);
      CheckWebhookURL();
      
      // Тестируем вебхук при запуске
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
   if(!g_SendToWebhook || g_WebhookURL == "")
      return;
   
   if(g_ShowDebugInfo)
      Print("=== Торговая транзакция: ", trans.type, " ===");
   
   // Обрабатываем различные типы транзакций
   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
         ProcessDealTransaction(trans);
         break;
         
      case TRADE_TRANSACTION_ORDER_ADD:
         ProcessOrderTransaction(trans);
         break;

      case TRADE_TRANSACTION_ORDER_UPDATE:
         ProcessOrderUpdateTransaction(trans, request);
         break;

         
      case TRADE_TRANSACTION_ORDER_DELETE:
         ProcessOrderDeleteTransaction(trans);
         break;
         
      case TRADE_TRANSACTION_POSITION:
         ProcessPositionTransaction(trans, request);
         break;
         
      case TRADE_TRANSACTION_REQUEST:
         ProcessRequestTransaction(trans, request);
         break;
         
      default:
         if(g_ShowDebugInfo)
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
void InitializeCache()
{
   cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
   ArrayResize(g_DedupKeys, 0);
   ArrayResize(g_DedupTimes, 0);
}

//+------------------------------------------------------------------+
//| Получение кэшированной информации об аккаунте                    |
//+------------------------------------------------------------------+
string GetCachedAccountInfo()
{
   if(cachedAccountInfo == "")
      cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   return cachedAccountInfo;
}

//+------------------------------------------------------------------+
//| Получение кэшированной информации о брокере                      |
//+------------------------------------------------------------------+
string GetCachedBrokerInfo()
{
   if(cachedBrokerInfo == "")
      cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
   return cachedBrokerInfo;
}

//+------------------------------------------------------------------+
//| Получение сектора символа                                        |
//+------------------------------------------------------------------+
int GetSymbolSector(string symbol)
{
   return (int)SymbolInfoInteger(symbol, SYMBOL_SECTOR);
}



//+------------------------------------------------------------------+
//| Обработка транзакции сделки                                      |
//+------------------------------------------------------------------+
void ProcessDealTransaction(const MqlTradeTransaction& trans)
{
   if(g_ShowDebugInfo)
      Print("Обработка транзакции сделки: ", trans.deal);
   
   if(HistoryDealSelect(trans.deal))
   {
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      
      if(g_ShowDebugInfo)
         Print("  Тип сделки: ", dealType, ", Вход: ", dealEntry);
      
             // Открытие позиции (вход в позицию)
       if(dealEntry == DEAL_ENTRY_IN)
       {
          if(g_ShowDebugInfo)
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
         if(g_ShowDebugInfo)
            Print("  Закрытие позиции: ", trans.deal);
         SendTradeNotification("CLOSE", trans.deal);
      }
      // Частичное закрытие
      else if(dealEntry == DEAL_ENTRY_OUT_BY)
      {
         if(g_ShowDebugInfo)
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
   if(g_ShowDebugInfo)
      Print("Обработка транзакции ордера: ", trans.order);
   
   if(OrderSelect(trans.order))
   {
      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      
      if(g_ShowDebugInfo)
         Print("  Создание отложенного ордера: ", trans.order, " типа: ", GetOrderTypeString(orderType));
      
      SendOrderNotification("PENDING", trans.order);
   }
}

//+------------------------------------------------------------------+
//| Обновление ордера                                                |
//+------------------------------------------------------------------+
void ProcessOrderUpdateTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   if(g_ShowDebugInfo)
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
   if(g_ShowDebugInfo)
      Print("Обработка удаления ордера: ", trans.order);
   
   // Проверяем состояние ордера в истории
   if(HistoryOrderSelect(trans.order))
   {
      ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE);
      
      if(g_ShowDebugInfo)
         Print("  Состояние удаленного ордера: ", orderState);
      
      if(orderState == ORDER_STATE_FILLED)
      {
         if(g_ShowDebugInfo)
            Print("  Ордер исполнен: ", trans.order);
         // Получим position_id из истории ордера
         ulong posId = HistoryOrderGetInteger(trans.order, ORDER_POSITION_ID);
         SendOrderNotification("ACTIVATED", trans.order, posId);
         // Ордер исполнен — кеш не используется
      }
      else if(orderState == ORDER_STATE_CANCELED)
      {
         if(g_ShowDebugInfo)
            Print("  Ордер отменен: ", trans.order);
         SendOrderNotification("CANCELED", trans.order);
         
      }
      else if(orderState == ORDER_STATE_PARTIAL)
      {
         if(g_ShowDebugInfo)
            Print("  Ордер частично исполнен: ", trans.order);
         SendOrderNotification("PARTIAL", trans.order);
         // PARTIAL в истории: отложка частично исполнена
      }
      else if(orderState == ORDER_STATE_REJECTED)
      {
         if(g_ShowDebugInfo)
            Print("  Ордер отклонен: ", trans.order);
         SendOrderNotification("REJECTED", trans.order);
         
      }
      else if(orderState == ORDER_STATE_EXPIRED)
      {
         if(g_ShowDebugInfo)
            Print("  Ордер истек: ", trans.order);
         SendOrderNotification("EXPIRED", trans.order);
         
      }
      else
      {
         if(g_ShowDebugInfo)
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
   if(g_ShowDebugInfo)
      Print("Изменение позиции: ", trans.position);
   
   if(PositionSelectByTicket(trans.position))
   {
      if(g_ShowDebugInfo)
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
   if(g_ShowDebugInfo)
      Print("Обработка транзакции запроса: ", trans.type);
   
   // Обрабатываем торговые запросы
   if(g_ShowDebugInfo)
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
   if(g_ShowDebugInfo)
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
   
   if(g_ShowDebugInfo)
      Print("JSON готов для отправки: ", json);
   
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Отправка уведомления об отложенном ордере                         |
//+------------------------------------------------------------------+
void SendOrderNotification(string orderType, ulong ticket, ulong positionTicket = 0)
{
   if(g_ShowDebugInfo)
      Print("Отправка уведомления об ордере: ", orderType, " тикет: ", ticket);
   
   // Валидируем данные перед отправкой
   if(!ValidateTradeData(ticket, orderType))
   {
      LogError("Данные не прошли валидацию для типа: " + orderType);
      return;
   }
   
   string json = CreateStandardJSON(orderType, ticket, positionTicket);
   
   if(g_ShowDebugInfo)
      Print("JSON готов для отправки: ", json);
   
   SendWebhookJSONWithRetry(json);
}

//+------------------------------------------------------------------+
//| Отправка события обновления SL/TP позиции                         |
//+------------------------------------------------------------------+
void SendPositionSltpUpdateNotification(ulong positionTicket)
{
   if(!g_SendToWebhook || g_WebhookURL == "")
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
   if(!g_SendToWebhook || g_WebhookURL == "")
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
string CreateBaseJSON(string eventType, ulong ticket)
{
   string json = "{";
   json += "\"event\":\"" + eventType + "\",";
   json += "\"ticket\":" + IntegerToString(ticket) + ",";
   json += "\"timestamp\":\"" + TimeToString(TimeCurrent()) + "\",";
   json += "\"account\":" + GetCachedAccountInfo() + ",";
   json += "\"broker\":\"" + GetCachedBrokerInfo() + "\"";
   
   // Получаем символ, сектор и position_id в зависимости от типа события
   string symbol = "";
   int sector = 0;
   ulong positionID = 0;
   
   if(eventType == "OPEN")
   {
      if(PositionSelectByTicket(ticket))
      {
         symbol = PositionGetString(POSITION_SYMBOL);
         sector = GetSymbolSector(symbol);
         positionID = ticket; // Для открытия позиции ticket уже является position_id
      }
   }
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
   {
      if(HistoryDealSelect(ticket))
      {
         symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         sector = GetSymbolSector(symbol);
         positionID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      }
   }
   else if(eventType == "PENDING")
   {
      if(OrderSelect(ticket))
      {
         symbol = OrderGetString(ORDER_SYMBOL);
         sector = GetSymbolSector(symbol);
         positionID = OrderGetInteger(ORDER_POSITION_ID);
      }
   }
   else if(eventType == "ACTIVATED" || eventType == "DELETE" || eventType == "CANCELED" || 
           eventType == "PARTIAL" || eventType == "REJECTED" || eventType == "EXPIRED")
   {
      if(HistoryOrderSelect(ticket))
      {
         symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
         sector = GetSymbolSector(symbol);
         positionID = HistoryOrderGetInteger(ticket, ORDER_POSITION_ID);
      }
   }
   
   // Добавляем информацию о символе и секторе
   if(symbol != "")
   {
      json += ",\"symbol\":\"" + EscapeJSONString(symbol) + "\"";
      json += ",\"sector\": \"" + EnumToString((ENUM_SYMBOL_SECTOR)sector) + "\"";;
   }
   
   // Добавляем position_id если он найден
   if(positionID != 0)
   {
      // Для открытия позиции ticket уже является position_id
      json += ",\"position_id\":" + IntegerToString(positionID);
   }
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
   {
      // Для сделок получаем position_id из сделки
      if(HistoryDealSelect(ticket))
      {
         ulong positionTicket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         if(positionTicket != 0)
            json += ",\"position_id\":" + IntegerToString(positionTicket);
      }
   }
   else if(eventType == "PENDING" || eventType == "ACTIVATED" || eventType == "DELETE" || 
           eventType == "CANCELED" || eventType == "PARTIAL" || eventType == "REJECTED" || eventType == "EXPIRED")
   {
      // Для ордеров получаем position_id из ордера
      bool orderSelected = false;
      if(eventType == "PENDING")
         orderSelected = OrderSelect(ticket);
      else
         orderSelected = HistoryOrderSelect(ticket);
         
      if(orderSelected)
      {
         ulong orderPositionID = 0;
         if(eventType == "PENDING")
            orderPositionID = OrderGetInteger(ORDER_POSITION_ID);
         else
            orderPositionID = HistoryOrderGetInteger(ticket, ORDER_POSITION_ID);
            
         if(orderPositionID != 0)
            json += ",\"position_id\":" + IntegerToString(orderPositionID);
      }
   }
   
   return json;
}

//+------------------------------------------------------------------+
//| Дедупликация: хэш события                                         |
//+------------------------------------------------------------------+
string BuildEventKey(string eventType, ulong ticket)
{
   // Составной ключ: тип + тикет. Можно расширить (symbol/position_id) при необходимости
   return eventType + ":" + IntegerToString((long)ticket);
}

//+------------------------------------------------------------------+
//| Дедупликация: очистка устаревших ключей                           |
//+------------------------------------------------------------------+
void PurgeOldDedupKeys()
{
   ulong now = GetTickCount64();
   int n = ArraySize(g_DedupKeys);
   if(n == 0)
      return;
   // Составим новые массивы без устаревших
   string newKeys[];
   ulong  newTimes[];
   ArrayResize(newKeys, 0);
   ArrayResize(newTimes, 0);
   for(int i=0;i<n;i++)
   {
      if(now - g_DedupTimes[i] <= (ulong)g_DedupWindowMs)
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

//+------------------------------------------------------------------+
//| Дедупликация: проверка и запись события                           |
//+------------------------------------------------------------------+
bool ShouldSendEvent(string eventType, ulong ticket)
{
   if(!g_EnableDedup)
      return true;

   // Дедупликацию пока применяем только для события закрытия позиции
   if(eventType != "CLOSE")
      return true;

   PurgeOldDedupKeys();

   string key = BuildEventKey(eventType, ticket);
   int n = ArraySize(g_DedupKeys);
   for(int i=0;i<n;i++)
   {
      if(g_DedupKeys[i] == key)
      {
         // Уже отправляли совсем недавно – подавим дубликат
         if(g_ShowDebugInfo)
            Print("Дедуп: подавлен повтор события ", key);
         return false;
      }
   }
   // Добавим ключ
   if(n >= g_DedupMaxSize)
   {
      // Уберем самый старый (голову)
      // Сдвиг вручную
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

//+------------------------------------------------------------------+
//| Создание JSON для позиции                                         |
//+------------------------------------------------------------------+
string CreatePositionJSON(ulong ticket)
{
   string json = "";
   if(PositionSelectByTicket(ticket))
   {
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      json += ",\"type\":\"" + ((type == POSITION_TYPE_BUY) ? "BUY" : "SELL") + "\"";
      json += ",\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2);
      json += ",\"price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5);
      json += ",\"profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2);
      json += ",\"swap\":" + DoubleToString(PositionGetDouble(POSITION_SWAP), 2);
      json += ",\"stop_loss\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5);
      json += ",\"take_profit\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5);
      json += ",\"comment\":\"" + EscapeJSONString(PositionGetString(POSITION_COMMENT)) + "\"";
   }
   return json;
}

//+------------------------------------------------------------------+
//| Создание JSON для сделки                                          |
//+------------------------------------------------------------------+
string CreateDealJSON(ulong ticket, string eventType)
{
   string json = "";
   if(HistoryDealSelect(ticket))
   {
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      json += ",\"type\":\"" + ((dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL") + "\"";
      json += ",\"volume\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2);
      json += ",\"price\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), 5);
      json += ",\"profit\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2);
      json += ",\"swap\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2);
      json += ",\"commission\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2);
      
      // Добавляем общий профит для событий закрытия
      if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
      {
         double totalProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                             HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                             HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         json += ",\"total_profit\":" + DoubleToString(totalProfit, 2);
      }
      json += ",\"comment\":\"" + EscapeJSONString(HistoryDealGetString(ticket, DEAL_COMMENT)) + "\"";
      
      if(eventType == "PARTIAL_CLOSE")
         json += ",\"partial_close\":true";
   }
   return json;
}

//+------------------------------------------------------------------+
//| Создание JSON для ордера                                          |
//+------------------------------------------------------------------+
string CreateOrderJSON(ulong ticket, bool isHistorical = false)
{
   string json = "";
   bool orderSelected = false;
   
   if(isHistorical)
      orderSelected = HistoryOrderSelect(ticket);
   else
      orderSelected = OrderSelect(ticket);
   
   if(orderSelected)
   {
      ENUM_ORDER_TYPE type;
      string comment;
      double volume, price, sl, tp;
      
      if(isHistorical)
      {
         type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE);
         volume = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
         price = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
         sl = HistoryOrderGetDouble(ticket, ORDER_SL);
         tp = HistoryOrderGetDouble(ticket, ORDER_TP);
         comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
      }
      else
      {
         type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         volume = OrderGetDouble(ORDER_VOLUME_INITIAL);
         price = OrderGetDouble(ORDER_PRICE_OPEN);
         sl = OrderGetDouble(ORDER_SL);
         tp = OrderGetDouble(ORDER_TP);
         comment = OrderGetString(ORDER_COMMENT);
      }
      
      json += ",\"type\":\"" + GetOrderTypeString(type) + "\"";
      json += ",\"volume\":" + DoubleToString(volume, 2);
      json += ",\"price\":" + DoubleToString(price, 5);
      json += ",\"stop_loss\":" + DoubleToString(sl, 5);
      json += ",\"take_profit\":" + DoubleToString(tp, 5);
      json += ",\"comment\":\"" + EscapeJSONString(comment) + "\"";
   }
   return json;
}

//+------------------------------------------------------------------+
//| JSON для обновления SL/TP ордера                                 |
//+------------------------------------------------------------------+
string CreateOrderSltpUpdateJSON(ulong ticket)
{
   string json = "";
   if(OrderSelect(ticket))
   {
      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);
      json += ",\"sl\":" + DoubleToString(sl, 5);
      json += ",\"tp\":" + DoubleToString(tp, 5);
      json += ",\"symbol\":\"" + EscapeJSONString(OrderGetString(ORDER_SYMBOL)) + "\"";
   }
   else if(HistoryOrderSelect(ticket))
   {
      double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
      double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
      json += ",\"sl\":" + DoubleToString(sl, 5);
      json += ",\"tp\":" + DoubleToString(tp, 5);
      json += ",\"symbol\":\"" + EscapeJSONString(HistoryOrderGetString(ticket, ORDER_SYMBOL)) + "\"";
   }
   return json;
}

//+------------------------------------------------------------------+
//| JSON для обновления SL/TP позиции                                 |
//+------------------------------------------------------------------+
string CreatePositionSltpUpdateJSON(ulong positionTicket)
{
   string json = "";
   if(PositionSelectByTicket(positionTicket))
   {
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      json += ",\"sl\":" + DoubleToString(sl, 5);
      json += ",\"tp\":" + DoubleToString(tp, 5);
      json += ",\"symbol\":\"" + EscapeJSONString(PositionGetString(POSITION_SYMBOL)) + "\"";
   }
   return json;
}

//+------------------------------------------------------------------+
//| Создание JSON для информации о позиции                            |
//+------------------------------------------------------------------+
string CreatePositionInfoJSON(ulong positionTicket)
{
   string json = "";
   if(PositionSelectByTicket(positionTicket))
   {
      json += ",\"position_ticket\":" + IntegerToString(positionTicket);
      json += ",\"position_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5);
      json += ",\"position_profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2);
   }
   return json;
}

//+------------------------------------------------------------------+
//| Создание стандартизированного JSON для всех типов событий         |
//+------------------------------------------------------------------+
string CreateStandardJSON(string eventType, ulong ticket, ulong positionTicket = 0)
{
   string json = CreateBaseJSON(eventType, ticket);
   
   if(eventType == "OPEN")
   {
      json += CreatePositionJSON(ticket);
   }
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
   {
      json += CreateDealJSON(ticket, eventType);
   }
   else if(eventType == "PENDING")
   {
      json += CreateOrderJSON(ticket, false);
   }
   else if(eventType == "ACTIVATED")
   {
      json += CreateOrderJSON(ticket, true);
      if(positionTicket != 0)
         json += CreatePositionInfoJSON(positionTicket);
   }
   else if(eventType == "ORDER_SLTP_UPDATE")
   {
      json += CreateOrderSltpUpdateJSON(ticket);
   }
   else if(eventType == "POSITION_SLTP_UPDATE")
   {
      json += CreatePositionSltpUpdateJSON(ticket);
   }
   else if(eventType == "DELETE" || eventType == "CANCELED" || eventType == "PARTIAL" || eventType == "REJECTED" || eventType == "EXPIRED")
   {
      json += CreateOrderJSON(ticket, true);
      if(eventType != "DELETE")
         json += ",\"state\":\"" + eventType + "\"";
   }
   
   json += "}";
   return json;
}



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
bool SendWebhookJSONWithRetry(string jsonData)
{
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
   {
      if(SendWebhookJSON(jsonData))
         return true;
      
      if(attempt < MaxRetries)
      {
         LogWarning("Попытка " + IntegerToString(attempt) + " не удалась, повтор через " + IntegerToString(RetryDelay) + " мс");
         Sleep(RetryDelay);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Универсальная функция отправки JSON на вебхук                    |
//+------------------------------------------------------------------+
bool SendWebhookJSON(string jsonData)
{
   if(!g_SendToWebhook || g_WebhookURL == "")
      return false;
      
   // Очищаем JSON от лишних символов
   string cleanJson = jsonData;
   StringTrimRight(cleanJson);
   StringTrimLeft(cleanJson);
   
   // Проверяем валидность JSON
   if(!IsValidJSON(cleanJson))
   {
      LogError("✗ Ошибка: Неверный формат JSON");
      LogError("  → Очищенный JSON: " + cleanJson);
      LogError("  → Длина JSON: " + IntegerToString(StringLen(cleanJson)));
      return false;
   }
   
   if(g_ShowDebugInfo)
   {
      Print("Очищенный JSON:", cleanJson);
   }
      
   string headers = "Content-Type: application/json; charset=utf-8\r\n";
   char post[], result[];
   
   StringToCharArray(cleanJson, post, 0, StringLen(cleanJson), CP_UTF8);
   int res = WebRequest("POST", g_WebhookURL, headers, g_WebhookTimeout, post, result, headers);
   
   // Получаем ответ сервера в UTF-8
   string serverResponse = CharArrayToString(result, 0, ArraySize(result), CP_UTF8);
   
   if(res == 200)
   {
      LogInfo("✓ JSON успешно отправлен на вебхук");
      return true;
   }
   else if(res == 422)
   {
      LogError("✗ Ошибка 422: Неверный формат данных");
      LogError("  → HTTP Status: 422 Unprocessable Entity");
      LogError("  → Сервер не может обработать запрос из-за неправильного формата");
      LogError("  → Отправленный JSON: " + jsonData);
      LogError("  → Ответ сервера: " + serverResponse);
      LogError("  → Проверьте формат данных на вашем сервере");
   }
   else if(res == -1)
   {
      LogError("✗ Ошибка -1: URL не добавлен в разрешенные адреса");
      LogError("  → Решение: Сервис -> Настройки -> Советники -> Добавить URL");
      LogError("  → URL: " + g_WebhookURL);
   }
   else if(res == -2)
   {
      LogError("✗ Ошибка -2: Неверный URL");
      LogError("  → Проверьте правильность URL: " + g_WebhookURL);
      LogError("  → URL должен начинаться с http:// или https://");
   }
   else if(res == -3)
   {
      LogError("✗ Ошибка -3: Таймаут запроса");
      LogError("  → Текущий таймаут: " + IntegerToString(g_WebhookTimeout) + " мс");
      LogError("  → Попробуйте увеличить значение WebhookTimeout");
   }
   else if(res == -4)
   {
      LogError("✗ Ошибка -4: Неверный HTTP-код ответа");
      LogError("  → Сервер вернул некорректный HTTP-код");
      LogError("  → Ответ сервера: " + serverResponse);
      LogError("  → Проверьте доступность сервера: " + g_WebhookURL);
   }
   else
   {
      LogError("✗ Неизвестная ошибка отправки. Код: " + IntegerToString(res));
      LogError("  → Ответ сервера: " + serverResponse);
      LogError("  → Проверьте подключение к интернету");
      LogError("  → Проверьте доступность сервера: " + g_WebhookURL);
   }
   
   return false;
}



//+------------------------------------------------------------------+
//| Принудительная проверка всех закрытых сделок                     |
//+------------------------------------------------------------------+
void ForceCheckClosedTrades()
{
   if(g_ShowDebugInfo)
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
//| Проверка URL вебхука                                             |
//+------------------------------------------------------------------+
void CheckWebhookURL()
{
   if(StringFind(g_WebhookURL, "http://") != 0 && StringFind(g_WebhookURL, "https://") != 0)
   {
      LogError("URL должен начинаться с http:// или https://");
      return;
   }
   

   
   LogInfo("URL: " + g_WebhookURL);
}

//+------------------------------------------------------------------+
//| Тестирование соединения с вебхуком                               |
//+------------------------------------------------------------------+
void TestWebhookConnection()
{
   // Создаем тестовый JSON
   string testJson = "{";
   testJson += "\"event\":\"test\",";
   testJson += "\"timestamp\":\"" + TimeToString(TimeCurrent()) + "\",";
   testJson += "\"message\":\"" + EscapeJSONString("Тестовое соединение от MT5 Webhook Expert") + "\",";
   testJson += "\"account\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ",";
   testJson += "\"symbol\":\"" + EscapeJSONString(Symbol()) + "\",";
   testJson += "\"sector\":" + IntegerToString(GetSymbolSector(Symbol()));
   testJson += "}";
   
   if(SendWebhookJSON(testJson))
   {
      LogInfo("✓ Соединение с вебхуком установлено");
   }
   else
   {
      LogError("✗ Не удалось установить соединение с вебхуком");
   }
}
