//+------------------------------------------------------------------+
//| Webhook client (send, retry, checks)                              |
//+------------------------------------------------------------------+

bool SendWebhookJSON(string jsonData)
{
   if(!SendToWebhook || WebhookURL == "")
      return false;
   string cleanJson = jsonData;
   StringTrimRight(cleanJson);
   StringTrimLeft(cleanJson);
   if(!IsValidJSON(cleanJson))
   {
      LogError("✗ Ошибка: Неверный формат JSON");
      LogError("  → Очищенный JSON: " + cleanJson);
      LogError("  → Длина JSON: " + IntegerToString(StringLen(cleanJson)));
      return false;
   }
   if(ShowDebugInfo)
      Print("Очищенный JSON:", cleanJson);
   string headers = "Content-Type: application/json; charset=utf-8\r\n";
   char post[], result[];
   StringToCharArray(cleanJson, post, 0, StringLen(cleanJson), CP_UTF8);
   int res = WebRequest("POST", WebhookURL, headers, WebhookTimeout, post, result, headers);
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
      LogError("  → URL: " + WebhookURL);
   }
   else if(res == -2)
   {
      LogError("✗ Ошибка -2: Неверный URL");
      LogError("  → Проверьте правильность URL: " + WebhookURL);
      LogError("  → URL должен начинаться с http:// или https://");
   }
   else if(res == -3)
   {
      LogError("✗ Ошибка -3: Таймаут запроса");
      LogError("  → Текущий таймаут: " + IntegerToString(WebhookTimeout) + " мс");
      LogError("  → Попробуйте увеличить значение WebhookTimeout");
   }
   else if(res == -4)
   {
      LogError("✗ Ошибка -4: Неверный HTTP-код ответа");
      LogError("  → Сервер вернул некорректный HTTP-код");
      LogError("  → Ответ сервера: " + serverResponse);
      LogError("  → Проверьте доступность сервера: " + WebhookURL);
   }
   else
   {
      LogError("✗ Неизвестная ошибка отправки. Код: " + IntegerToString(res));
      LogError("  → Ответ сервера: " + serverResponse);
      LogError("  → Проверьте подключение к интернету");
      LogError("  → Проверьте доступность сервера: " + WebhookURL);
   }
   return false;
}

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

void CheckWebhookURL()
{
   if(StringFind(WebhookURL, "http://") != 0 && StringFind(WebhookURL, "https://") != 0)
   {
      LogError("URL должен начинаться с http:// или https://");
      return;
   }
   LogInfo("URL: " + WebhookURL);
}

void TestWebhookConnection()
{
   string testJson = "{";
   testJson += "\"event\":\"test\",";
   testJson += "\"timestamp\":\"" + ToIso8601(TimeCurrent()) + "\",";
   testJson += "\"message\":\"" + EscapeJSONString("Тестовое соединение от MT5 Webhook Expert") + "\",";
   testJson += "\"account\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ",";
   testJson += "\"symbol\":\"" + EscapeJSONString(Symbol()) + "\",";
   testJson += "\"sector\":" + IntegerToString(GetSymbolSector(Symbol())) + ",";
   testJson += "\"schema_version\":\"" JSON_SCHEMA_VERSION "\",";
   testJson += "\"ea_version\":\"" EA_VERSION "\"";
   testJson += "}";
   if(SendWebhookJSON(testJson))
      LogInfo("✓ Соединение с вебхуком установлено");
   else
      LogError("✗ Не удалось установить соединение с вебхуком");
}


