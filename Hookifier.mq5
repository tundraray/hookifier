//+------------------------------------------------------------------+
//|                                                    Hookifier.mq5 |
//|                             Copyright 2025, Lavara Software Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Lavara Software Ltd."
#property link      "https://www.mql5.com"
#property version   "1.22"
#property description "Hookifier: Эксперт для отправки уведомлений о сделках на вебхук"

// Версии схемы и эксперта (держите в синхронизации с #property version)
#define JSON_SCHEMA_VERSION "1.0"
#define EA_VERSION          "1.22"

#include "logger.mqh"
#include "utils.mqh"
#include "dedup.mqh"
#include "webhook_client.mqh"
#include "json_builder.mqh"

//--- Входные параметры
input group   "=== Настройки вебхука ==="
input bool     SendToWebhook = true;    // Отправлять данные на вебхук
input string   WebhookURL = "https://my-test-webhook.com/endpoint";          // URL вашего вебхука
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





//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo("=== Webhook Expert Advisor инициализирован ===");
   
   // Инициализируем кэш
   InitializeCache();
   
   // Инициализируем оптимизированную дедупликацию
   InitDedup(1024, DedupWindowMs);
   
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
   
   
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   
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
//| Отправка уведомления об отложенном ордере                        |
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
//| Отправка события обновления SL/TP позиции                        |
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
//| Отправка события обновления SL/TP ордера                         |
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
//| Получение строкового представления типа ордера                   |
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
   LogInfo("Dedup Stats: " + GetDedupStats());
   LogInfo("=========================");
}
