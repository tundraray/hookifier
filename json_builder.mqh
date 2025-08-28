//+------------------------------------------------------------------+
//| Simple JSON builder and payload creators                          |
//+------------------------------------------------------------------+

class JsonBuilder
{
private:
   string buffer;
   bool   first;
public:
   void Begin()
   {
      buffer = "{";
      first = true;
   }
   void End()
   {
      buffer += "}";
   }
   string Str()
   {
      return buffer;
   }
   void CommaIfNeeded()
   {
      if(!first) buffer += ",";
      first = false;
   }
   void PropString(string key, string value)
   {
      CommaIfNeeded();
      buffer += "\"" + key + "\":\"" + EscapeJSONString(value) + "\"";
   }
   void PropNumber(string key, double value, int digits = 0)
   {
      CommaIfNeeded();
      if(digits > 0)
         buffer += "\"" + key + "\":" + DoubleToString(value, digits);
      else
         buffer += "\"" + key + "\":" + DoubleToString(value, 0);
   }
   void PropInteger(string key, long value)
   {
      CommaIfNeeded();
      buffer += "\"" + key + "\":" + IntegerToString(value);
   }
   void PropBool(string key, bool value)
   {
      CommaIfNeeded();
      buffer += "\"" + key + "\":" + (value ? "true" : "false");
   }
};

string CreateBaseJSON(string eventType, ulong ticket)
{
   JsonBuilder jb;
   jb.Begin();
   jb.PropString("event", eventType);
   jb.PropInteger("ticket", (long)ticket);
   jb.PropString("timestamp", ToIso8601(TimeCurrent()));
   jb.PropInteger("account", (long)AccountInfoInteger(ACCOUNT_LOGIN));
   jb.PropString("broker", AccountInfoString(ACCOUNT_COMPANY));
   jb.PropString("schema_version", JSON_SCHEMA_VERSION);
   jb.PropString("ea_version", EA_VERSION);

   string symbol = "";
   int sector = 0;
   ulong positionID = 0;
   if(eventType == "OPEN")
   {
      if(PositionSelectByTicket(ticket))
      {
         symbol = PositionGetString(POSITION_SYMBOL);
         sector = GetSymbolSector(symbol);
         positionID = ticket;
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

   if(symbol != "")
   {
      jb.PropString("symbol", symbol);
      jb.PropString("sector", EnumToString((ENUM_SYMBOL_SECTOR)sector));
   }
   if(positionID != 0)
   {
      jb.PropInteger("position_id", (long)positionID);
   }
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
   {
      if(HistoryDealSelect(ticket))
      {
         ulong positionTicket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         if(positionTicket != 0)
            jb.PropInteger("position_id", (long)positionTicket);
      }
   }
   else if(eventType == "PENDING" || eventType == "ACTIVATED" || eventType == "DELETE" || 
           eventType == "CANCELED" || eventType == "PARTIAL" || eventType == "REJECTED" || eventType == "EXPIRED")
   {
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
            jb.PropInteger("position_id", (long)orderPositionID);
      }
   }

   jb.End();
   return jb.Str();
}

string CreatePositionJSON(ulong ticket)
{
   string json = "";
   if(PositionSelectByTicket(ticket))
   {
      JsonBuilder jb;
      jb.Begin();
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string symbol = PositionGetString(POSITION_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropString("type", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL");
      jb.PropNumber("volume", PositionGetDouble(POSITION_VOLUME), 2);
      jb.PropNumber("price", PositionGetDouble(POSITION_PRICE_OPEN), digits);
      jb.PropNumber("profit", PositionGetDouble(POSITION_PROFIT), 2);
      jb.PropNumber("swap", PositionGetDouble(POSITION_SWAP), 2);
      jb.PropNumber("stop_loss", PositionGetDouble(POSITION_SL), digits);
      jb.PropNumber("take_profit", PositionGetDouble(POSITION_TP), digits);
      jb.PropString("comment", PositionGetString(POSITION_COMMENT));
      jb.End();
      json = jb.Str();
      json = StringSubstr(json, 1, StringLen(json)-2); // remove { ... }
   }
   return json;
}

string CreateDealJSON(ulong ticket, string eventType)
{
   string json = "";
   if(HistoryDealSelect(ticket))
   {
      JsonBuilder jb;
      jb.Begin();
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropString("type", (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL");
      jb.PropNumber("volume", HistoryDealGetDouble(ticket, DEAL_VOLUME), 2);
      jb.PropNumber("price", HistoryDealGetDouble(ticket, DEAL_PRICE), digits);
      jb.PropNumber("profit", HistoryDealGetDouble(ticket, DEAL_PROFIT), 2);
      jb.PropNumber("swap", HistoryDealGetDouble(ticket, DEAL_SWAP), 2);
      jb.PropNumber("commission", HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2);
      if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
      {
         double totalProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                              HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                              HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         jb.PropNumber("total_profit", totalProfit, 2);
      }
      jb.PropString("comment", HistoryDealGetString(ticket, DEAL_COMMENT));
      if(eventType == "PARTIAL_CLOSE")
         jb.PropBool("partial_close", true);
      jb.End();
      json = jb.Str();
      json = StringSubstr(json, 1, StringLen(json)-2);
   }
   return json;
}

string CreateOrderJSON(ulong ticket, bool isHistorical = false)
{
   string json = "";
   bool orderSelected = isHistorical ? HistoryOrderSelect(ticket) : OrderSelect(ticket);
   if(orderSelected)
   {
      JsonBuilder jb;
      jb.Begin();
      ENUM_ORDER_TYPE type;
      string comment;
      double volume, price, sl, tp;
      string symbol;
      if(isHistorical)
      {
         type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE);
         volume = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
         price = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
         sl = HistoryOrderGetDouble(ticket, ORDER_SL);
         tp = HistoryOrderGetDouble(ticket, ORDER_TP);
         comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
         symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
      }
      else
      {
         type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         volume = OrderGetDouble(ORDER_VOLUME_INITIAL);
         price = OrderGetDouble(ORDER_PRICE_OPEN);
         sl = OrderGetDouble(ORDER_SL);
         tp = OrderGetDouble(ORDER_TP);
         comment = OrderGetString(ORDER_COMMENT);
         symbol = OrderGetString(ORDER_SYMBOL);
      }
      int digits = GetDigitsForSymbol(symbol);
      jb.PropString("type", GetOrderTypeString(type));
      jb.PropNumber("volume", volume, 2);
      jb.PropNumber("price", price, digits);
      jb.PropNumber("stop_loss", sl, digits);
      jb.PropNumber("take_profit", tp, digits);
      jb.PropString("comment", comment);
      jb.End();
      json = jb.Str();
      json = StringSubstr(json, 1, StringLen(json)-2);
   }
   return json;
}

string CreateOrderSltpUpdateJSON(ulong ticket)
{
   string json = "";
   JsonBuilder jb;
   jb.Begin();
   if(OrderSelect(ticket))
   {
      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);
      string symbol = OrderGetString(ORDER_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropNumber("sl", sl, digits);
      jb.PropNumber("tp", tp, digits);
      jb.PropString("symbol", symbol);
   }
   else if(HistoryOrderSelect(ticket))
   {
      double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
      double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
      string symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropNumber("sl", sl, digits);
      jb.PropNumber("tp", tp, digits);
      jb.PropString("symbol", symbol);
   }
   jb.End();
   json = jb.Str();
   json = StringSubstr(json, 1, StringLen(json)-2);
   return json;
}

string CreatePositionSltpUpdateJSON(ulong positionTicket)
{
   string json = "";
   if(PositionSelectByTicket(positionTicket))
   {
      JsonBuilder jb;
      jb.Begin();
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      string symbol = PositionGetString(POSITION_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropNumber("sl", sl, digits);
      jb.PropNumber("tp", tp, digits);
      jb.PropString("symbol", symbol);
      jb.End();
      json = jb.Str();
      json = StringSubstr(json, 1, StringLen(json)-2);
   }
   return json;
}

string CreatePositionInfoJSON(ulong positionTicket)
{
   string json = "";
   if(PositionSelectByTicket(positionTicket))
   {
      JsonBuilder jb;
      jb.Begin();
      string symbol = PositionGetString(POSITION_SYMBOL);
      int digits = GetDigitsForSymbol(symbol);
      jb.PropInteger("position_ticket", (long)positionTicket);
      jb.PropNumber("position_price", PositionGetDouble(POSITION_PRICE_OPEN), digits);
      jb.PropNumber("position_profit", PositionGetDouble(POSITION_PROFIT), 2);
      jb.End();
      json = jb.Str();
      json = StringSubstr(json, 1, StringLen(json)-2);
   }
   return json;
}

string CreateStandardJSON(string eventType, ulong ticket, ulong positionTicket = 0)
{
   string json = CreateBaseJSON(eventType, ticket);
   if(eventType == "OPEN")
      json += CreatePositionJSON(ticket);
   else if(eventType == "CLOSE" || eventType == "PARTIAL_CLOSE")
      json += CreateDealJSON(ticket, eventType);
   else if(eventType == "PENDING")
      json += CreateOrderJSON(ticket, false);
   else if(eventType == "ACTIVATED")
   {
      json += CreateOrderJSON(ticket, true);
      if(positionTicket != 0)
         json += CreatePositionInfoJSON(positionTicket);
   }
   else if(eventType == "ORDER_SLTP_UPDATE")
      json += CreateOrderSltpUpdateJSON(ticket);
   else if(eventType == "POSITION_SLTP_UPDATE")
      json += CreatePositionSltpUpdateJSON(ticket);
   else if(eventType == "DELETE" || eventType == "CANCELED" || eventType == "PARTIAL" || eventType == "REJECTED" || eventType == "EXPIRED")
   {
      json += CreateOrderJSON(ticket, true);
      if(eventType != "DELETE")
         json += ",\"state\":\"" + eventType + "\"";
   }
   json += "}";
   return json;
}


