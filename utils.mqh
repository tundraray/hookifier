//+------------------------------------------------------------------+
//| Utils: JSON, time, symbol info, cache                             |
//+------------------------------------------------------------------+

string cachedAccountInfo = "";
string cachedBrokerInfo = "";

string GetCachedAccountInfo()
{
   if(cachedAccountInfo == "")
      cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   return cachedAccountInfo;
}

string GetCachedBrokerInfo()
{
   if(cachedBrokerInfo == "")
      cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
   return cachedBrokerInfo;
}

void InitializeCache()
{
   cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
}

bool IsValidJSON(string jsonData)
{
   if(StringLen(jsonData) == 0)
      return false;
   if(StringGetCharacter(jsonData, 0) != '{')
      return false;
   if(StringGetCharacter(jsonData, StringLen(jsonData) - 1) != '}')
      return false;
   string trimmed = jsonData;
   StringTrimRight(trimmed);
   if(StringLen(trimmed) != StringLen(jsonData))
   {
      LogWarning("⚠ Обнаружены лишние символы в конце JSON");
      return false;
   }
   return true;
}

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
         case 8:    result += "\\b";  break;
         case 12:   result += "\\f";  break;
         case 10:   result += "\\n";  break;
         case 13:   result += "\\r";  break;
         case 9:    result += "\\t";  break;
         default:
            if(ch < 32 || ch > 126)
               result += "\\u" + StringFormat("%04X", ch);
            else
               result += ShortToString(ch);
            break;
      }
   }
   return result;
}

string ToIso8601(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

int GetDigitsForSymbol(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 5;
   return digits;
}

int GetSymbolSector(string symbol)
{
   return (int)SymbolInfoInteger(symbol, SYMBOL_SECTOR);
}


