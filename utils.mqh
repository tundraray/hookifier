//+------------------------------------------------------------------+
//| Utils - Модуль утилит и вспомогательных функций                  |
//| Содержит функции для кэширования, форматирования и обработки     |
//+------------------------------------------------------------------+

// Глобальные переменные для кэширования часто используемых данных
string cachedAccountInfo = "";  // Кэш номера счета
string cachedBrokerInfo = "";   // Кэш названия брокера

//+------------------------------------------------------------------+
//| Инициализация кэша при запуске советника                         |
//| Сохраняет в памяти часто используемые данные счета               |
//| для уменьшения количества системных вызовов                      |
//+------------------------------------------------------------------+
void InitializeCache()
{
   cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
}

//+------------------------------------------------------------------+
//| Получение кэшированного номера счета                             |
//| Возвращает сохраненный номер счета, при необходимости            |
//| обновляет кэш                                                    |
//| Возвращает: строку с номером торгового счета                     |
//+------------------------------------------------------------------+
string GetCachedAccountInfo()
{
   if(cachedAccountInfo == "")
      cachedAccountInfo = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   return cachedAccountInfo;
}

//+------------------------------------------------------------------+
//| Получение кэшированного названия брокера                         |
//| Возвращает экранированное название брокерской компании           |
//| При необходимости обновляет кэш                                  |
//| Возвращает: экранированную строку с названием брокера            |
//+------------------------------------------------------------------+
string GetCachedBrokerInfo()
{
   if(cachedBrokerInfo == "")
      cachedBrokerInfo = EscapeJSONString(AccountInfoString(ACCOUNT_COMPANY));
   return cachedBrokerInfo;
}

//+------------------------------------------------------------------+
//| Проверка валидности JSON строки                                  |
//| jsonData - строка для проверки                                   |
//| Проверяет базовую структуру JSON:                                |
//| - Не пустая строка                                               |
//| - Начинается с { и заканчивается на }                           |
//| - Нет лишних пробелов в конце                                    |
//| Возвращает: true если JSON валиден, false если нет               |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Экранирование специальных символов для JSON                      |
//| text - исходная строка                                           |
//| Экранирует специальные символы согласно JSON спецификации:       |
//| " -> \", \ -> \\, переводы строк, табуляции и т.д.              |
//| Unicode символы конвертируются в \uXXXX формат                   |
//| Возвращает: экранированную строку для использования в JSON        |
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
         case '"':  result += "\\\""; break;  // Двойные кавычки
         case '\\': result += "\\\\"; break;  // Обратный слеш
         case 8:    result += "\\b";  break;  // Backspace
         case 12:   result += "\\f";  break;  // Form feed
         case 10:   result += "\\n";  break;  // Line feed (новая строка)
         case 13:   result += "\\r";  break;  // Carriage return
         case 9:    result += "\\t";  break;  // Табуляция
         default:
            if(ch < 32 || ch > 126)  // Непечатные и не-ASCII символы
            {
               // Конвертируем в Unicode escape последовательность
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
//| Форматирование времени в ISO-8601 формат с UTC                   |
//| t - время для форматирования                                     |
//| Преобразует время MetaTrader в стандартный ISO формат            |
//| Формат: YYYY-MM-DDTHH:MM:SSZ                                     |
//| Z в конце означает UTC время                                     |
//| Возвращает: строку в ISO-8601 формате                           |
//+------------------------------------------------------------------+
string ToIso8601(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   // Форматируем в стандарт ISO-8601 с индикатором UTC (Z)
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

//+------------------------------------------------------------------+
//| Получение точности (количества знаков после запятой) для символа |
//| symbol - торговый символ                                         |
//| Запрашивает у брокера точность для данного символа               |
//| Если не удается получить, возвращает 5 (стандарт для forex)     |
//| Возвращает: количество знаков после запятой для цен              |
//+------------------------------------------------------------------+
int GetDigitsForSymbol(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 5; // Значение по умолчанию для forex
   return digits;
}

//+------------------------------------------------------------------+
//| Получение сектора рынка для символа                              |
//| symbol - торговый символ                                         |
//| Определяет к какому сектору относится инструмент:                |
//| forex, stocks, crypto, commodities и т.д.                        |
//| Возвращает: код сектора согласно ENUM_SYMBOL_SECTOR              |
//+------------------------------------------------------------------+
int GetSymbolSector(string symbol)
{
   return (int)SymbolInfoInteger(symbol, SYMBOL_SECTOR);
}