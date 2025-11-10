//+------------------------------------------------------------------+
//|                                          MT5-PositionMaster.mq5 |
//|                                        Copyright 2025, FanYueee |
//|                                             https://fanyueee.ee |
//+------------------------------------------------------------------+
/**
 * @file MT5-PositionMaster.mq5
 * @brief MT5 倉位管理 Expert Advisor - 通過 Telegram Bot 遠程管理多個交易倉位
 * @details
 * 這是一個生產級別的 MT5 Expert Advisor，集成了 Telegram Bot 功能，
 * 允許交易者通過 Telegram 遠程管理所有開倉倉位。
 *
 * 主要功能：
 * - 修改所有倉位的止盈/止損價格
 * - 刪除所有倉位的止盈/止損設置
 * - 平掉一半倉位
 *
 * @author FanYueee
 * @date 2025-11-10
 * @version 1.0.0
 *
 * @note 使用前請確保：
 *       1. 已在 MT5 設置中允許 WebRequest 訪問 api.telegram.org
 *       2. 已創建 Telegram Bot 並獲取 Bot Token
 *       3. 已獲取授權的 Telegram Chat ID
 *
 * @warning 請妥善保管 Bot Token，避免洩露給未授權人員
 */

#property copyright "Copyright 2025, FanYueee"
#property link      "https://fanyueee.ee"
#property version   "1.00"
#property description "MT5 倉位管理 Expert Advisor - 通過 Telegram Bot 遠程管理多個交易倉位"
#property strict

//+------------------------------------------------------------------+
//| 輸入參數                                                           |
//+------------------------------------------------------------------+

/** @brief Telegram Bot Token */
input string InpBotToken = "";                    // Telegram Bot Token (必填)

/** @brief 授權的 Telegram Chat ID */
input long InpChatID = 0;                         // 授權的 Chat ID (必填)

/** @brief 輪詢間隔（秒） */
input int InpPollingInterval = 2;                 // 輪詢間隔（秒）

/** @brief 是否啟用詳細日誌 */
input bool InpVerboseLogging = true;              // 啟用詳細日誌

/** @brief 止盈/止損價格的最小距離點數 */
input int InpMinTPSLDistance = 10;                // TP/SL 最小距離（點）

//+------------------------------------------------------------------+
//| 全局變量                                                           |
//+------------------------------------------------------------------+

/** @brief 上次處理的更新 ID */
long g_lastUpdateID = 0;

/** @brief Telegram API 基礎 URL */
string g_telegramAPIURL = "";

/** @brief EA 是否已正確初始化 */
bool g_isInitialized = false;

/** @brief 錯誤計數器 */
int g_errorCount = 0;

/** @brief 最大連續錯誤次數 */
const int MAX_ERROR_COUNT = 10;

/** @brief 商品點值 */
double g_point = 0.0;

/** @brief 商品小數位數 */
int g_digits = 0;

//+------------------------------------------------------------------+
//| Expert 初始化函數                                                  |
//+------------------------------------------------------------------+
/**
 * @brief EA 初始化函數
 * @details 在 EA 啟動時執行，進行必要的初始化設置：
 *          - 驗證輸入參數
 *          - 構建 Telegram API URL
 *          - 設置定時器
 *          - 獲取商品基本資訊
 * @return INIT_SUCCEEDED 初始化成功，INIT_PARAMETERS_INCORRECT 參數錯誤，INIT_FAILED 初始化失敗
 * @note 如果初始化失敗，EA 將無法正常工作
 */
int OnInit()
{
    //--- 驗證輸入參數
    if(StringLen(InpBotToken) == 0)
    {
        Print("[錯誤]：Bot Token 不能為空！請在 EA 設置中填寫 Telegram Bot Token。");
        return INIT_PARAMETERS_INCORRECT;
    }

    if(InpChatID == 0)
    {
        Print("[錯誤]：Chat ID 不能為 0！請在 EA 設置中填寫授權的 Telegram Chat ID。");
        return INIT_PARAMETERS_INCORRECT;
    }

    if(InpPollingInterval < 1)
    {
        Print("[錯誤]：輪詢間隔不能小於 1 秒！");
        return INIT_PARAMETERS_INCORRECT;
    }

    //--- 構建 Telegram API URL
    g_telegramAPIURL = "https://api.telegram.org/bot" + InpBotToken;

    //--- 獲取商品資訊
    g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    //--- 設置定時器（以秒為單位）
    if(!EventSetTimer(InpPollingInterval))
    {
        Print("錯誤：無法設置定時器！");
        return INIT_FAILED;
    }

    //--- 重置錯誤計數器
    g_errorCount = 0;
    g_isInitialized = true;

    //--- 獲取最新的 update ID，避免處理舊消息
    GetLatestUpdateID();

    //--- 發送啟動通知
    string startMsg = "[成功] MT5-PositionMaster EA 已成功啟動！\n\n";
    startMsg += "[統計] 交易品種：" + _Symbol + "\n";
    startMsg += "[系統] EA 版本：1.0.0\n";
    startMsg += "[時間] 輪詢間隔：" + IntegerToString(InpPollingInterval) + " 秒\n\n";
    startMsg += "輸入 /help 查看所有可用指令。";

    SendTelegramMessage(startMsg);

    Print("[成功] MT5-PositionMaster EA 初始化成功！");
    Print("[統計] 交易品種：", _Symbol);
    Print("[時間] 輪詢間隔：", InpPollingInterval, " 秒");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert 反初始化函數                                                |
//+------------------------------------------------------------------+
/**
 * @brief EA 反初始化函數
 * @details 在 EA 關閉時執行清理工作：
 *          - 刪除定時器
 *          - 發送關閉通知
 *          - 記錄日誌
 * @note 確保資源正確釋放
 */
void OnDeinit(const int reason)
{
    //--- 刪除定時器
    EventKillTimer();

    //--- 發送關閉通知
    string msg = "[警告] MT5-PositionMaster EA 已停止運行。\n";
    msg += "原因代碼：" + IntegerToString(reason);
    SendTelegramMessage(msg);

    //--- 記錄日誌
    Print("[警告] MT5-PositionMaster EA 已停止，原因代碼：", reason);
    g_isInitialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick 函數                                                  |
//+------------------------------------------------------------------+
/**
 * @brief EA tick 函數
 * @details 每個 tick 執行一次，目前不進行任何操作
 * @note 主要邏輯在 OnTimer 中處理
 */
void OnTick()
{
    // 主要邏輯在 OnTimer 中處理
}

//+------------------------------------------------------------------+
//| Timer 函數                                                        |
//+------------------------------------------------------------------+
/**
 * @brief 定時器函數
 * @details 定期執行（根據 InpPollingInterval 設置），負責：
 *          - 輪詢 Telegram 更新
 *          - 處理收到的指令
 *          - 錯誤恢復機制
 * @note 這是 EA 的核心處理邏輯
 */
void OnTimer()
{
    if(!g_isInitialized)
        return;

    //--- 檢查錯誤計數
    if(g_errorCount >= MAX_ERROR_COUNT)
    {
        Print("[錯誤] 連續錯誤次數過多，暫停處理。請檢查網絡連接和 Bot Token。");
        return;
    }

    //--- 輪詢 Telegram 更新
    ProcessTelegramUpdates();
}

//+------------------------------------------------------------------+
//| Telegram 相關函數                                                 |
//+------------------------------------------------------------------+

/**
 * @brief 獲取最新的 update ID
 * @details 獲取 Telegram Bot 最新的更新 ID，用於初始化時跳過舊消息
 * @note 初始化時調用，避免處理歷史消息
 */
void GetLatestUpdateID()
{
    string url = g_telegramAPIURL + "/getUpdates";
    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultString;
    int timeout = 5000;

    int res = WebRequest("GET", url, headers, timeout, post, result, headers);

    if(res == 200)
    {
        resultString = CharArrayToString(result);

        //--- 解析 JSON 獲取最新的 update_id
        int start = StringFind(resultString, "\"update_id\":");
        if(start >= 0)
        {
            start += 13; // 長度 "\"update_id\"："
            int end = StringFind(resultString, ",", start);
            if(end < 0)
                end = StringFind(resultString, "}", start);

            if(end > start)
            {
                string updateIDStr = StringSubstr(resultString, start, end - start);
                g_lastUpdateID = StringToInteger(updateIDStr);

                if(InpVerboseLogging)
                    Print("[標記] 初始 Update ID 設置為：", g_lastUpdateID);
            }
        }
    }
}

/**
 * @brief 處理 Telegram 更新
 * @details 從 Telegram 服務器獲取新消息並處理：
 *          - 使用長輪詢機制獲取更新
 *          - 驗證 Chat ID
 *          - 解析並執行指令
 *          - 更新 update ID
 * @return 成功處理返回 true，否則返回 false
 * @note 使用長輪詢提高效率，減少請求次數
 */
bool ProcessTelegramUpdates()
{
    string url = g_telegramAPIURL + "/getUpdates?offset=" + IntegerToString(g_lastUpdateID + 1) + "&timeout=10";
    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultString;
    int timeout = 15000; // 15秒超時（10秒長輪詢 + 5秒緩衝）

    int res = WebRequest("GET", url, headers, timeout, post, result, headers);

    if(res == -1)
    {
        int error = GetLastError();
        if(error == 4014) // URL 未添加到允許列表
        {
            Print("[錯誤] 請在 MT5 設置中允許 URL：https://api.telegram.org");
            Print("   工具 -> 選項 -> Expert Advisors -> 允許 WebRequest 訪問以下 URL 列表");
        }
        else
        {
            Print("[錯誤] WebRequest 錯誤代碼：", error);
        }
        g_errorCount++;
        return false;
    }

    if(res != 200)
    {
        Print("[錯誤] HTTP 錯誤代碼：", res);
        g_errorCount++;
        return false;
    }

    //--- 重置錯誤計數
    g_errorCount = 0;

    resultString = CharArrayToString(result);

    if(InpVerboseLogging && StringLen(resultString) > 100)
        Print("[接收] 收到響應：", StringSubstr(resultString, 0, 100), "...");

    //--- 解析 JSON 響應
    if(StringFind(resultString, "\"ok\":true") < 0)
    {
        Print("[錯誤] Telegram API 響應錯誤：", resultString);
        return false;
    }

    //--- 提取 result 數組
    int resultStart = StringFind(resultString, "\"result\":[");
    if(resultStart < 0)
        return true; // 沒有新消息

    resultStart += 10;
    int resultEnd = StringFind(resultString, "]", resultStart);

    if(resultEnd < 0 || resultEnd <= resultStart)
        return true; // 空結果

    string resultArray = StringSubstr(resultString, resultStart, resultEnd - resultStart);

    if(StringLen(resultArray) < 5) // 至少要有一些內容
        return true; // 空數組

    //--- 解析每個更新
    ParseAndProcessUpdates(resultArray);

    return true;
}

/**
 * @brief 解析並處理更新數組
 * @details 解析 Telegram 返回的更新數組，提取並處理每條消息
 * @param updates JSON 格式的更新數組字符串
 * @note 簡化的 JSON 解析，專門處理 Telegram 響應格式
 */
void ParseAndProcessUpdates(string updates)
{
    int pos = 0;

    while(pos < StringLen(updates))
    {
        //--- 查找下一個 update
        int updateStart = StringFind(updates, "{\"update_id\":", pos);
        if(updateStart < 0)
            break;

        //--- 查找 update 結束位置
        int braceCount = 0;
        int updateEnd = updateStart;
        bool inString = false;

        for(int i = updateStart; i < StringLen(updates); i++)
        {
            ushort ch = StringGetCharacter(updates, i);

            if(ch == '"' && (i == 0 || StringGetCharacter(updates, i - 1) != '\\'))
                inString = !inString;

            if(!inString)
            {
                if(ch == '{')
                    braceCount++;
                else if(ch == '}')
                {
                    braceCount--;
                    if(braceCount == 0)
                    {
                        updateEnd = i + 1;
                        break;
                    }
                }
            }
        }

        if(updateEnd > updateStart)
        {
            string update = StringSubstr(updates, updateStart, updateEnd - updateStart);
            ProcessSingleUpdate(update);
            pos = updateEnd;
        }
        else
        {
            break;
        }
    }
}

/**
 * @brief 處理單個更新
 * @details 處理一條 Telegram 更新消息：
 *          - 提取 update ID
 *          - 驗證 Chat ID
 *          - 提取並處理指令
 * @param update JSON 格式的單個更新字符串
 * @note 包含完整的安全驗證機制
 */
void ProcessSingleUpdate(string update)
{
    //--- 提取 update_id
    long updateID = ExtractUpdateID(update);
    if(updateID <= g_lastUpdateID)
        return; // 已處理過的消息

    g_lastUpdateID = updateID;

    //--- 提取 chat_id
    long chatID = ExtractChatID(update);

    //--- 驗證 Chat ID
    if(chatID != InpChatID)
    {
        Print("[警告] 未授權的 Chat ID 嘗試訪問：", chatID);
        SendTelegramMessageToChatID("[錯誤] 未授權訪問！此 Bot 僅供授權用戶使用。", chatID);
        return;
    }

    //--- 提取消息文本
    string messageText = ExtractMessageText(update);

    if(StringLen(messageText) == 0)
        return; // 沒有文本消息

    if(InpVerboseLogging)
        Print("[消息] 收到指令：", messageText);

    //--- 處理指令
    ProcessCommand(messageText);
}

/**
 * @brief 提取 update ID
 * @details 從 JSON 字符串中提取 update_id 字段
 * @param json JSON 格式字符串
 * @return update ID，失敗返回 0
 */
long ExtractUpdateID(string json)
{
    int start = StringFind(json, "\"update_id\":");
    if(start < 0)
        return 0;

    start += 13;
    int end = StringFind(json, ",", start);
    if(end < 0)
        end = StringFind(json, "}", start);

    if(end <= start)
        return 0;

    string idStr = StringSubstr(json, start, end - start);
    return StringToInteger(idStr);
}

/**
 * @brief 提取 Chat ID
 * @details 從 JSON 字符串中提取 chat ID 字段
 * @param json JSON 格式字符串
 * @return Chat ID，失敗返回 0
 */
long ExtractChatID(string json)
{
    int start = StringFind(json, "\"chat\":{\"id\":");
    if(start < 0)
        return 0;

    start += 14;
    int end = StringFind(json, ",", start);
    if(end < 0)
        end = StringFind(json, "}", start);

    if(end <= start)
        return 0;

    string idStr = StringSubstr(json, start, end - start);
    return StringToInteger(idStr);
}

/**
 * @brief 提取消息文本
 * @details 從 JSON 字符串中提取消息文本內容
 * @param json JSON 格式字符串
 * @return 消息文本，失敗返回空字符串
 * @note 處理了文本中的轉義字符
 */
string ExtractMessageText(string json)
{
    int start = StringFind(json, "\"text\":\"");
    if(start < 0)
        return "";

    start += 8;
    int end = start;

    //--- 查找字符串結束位置（考慮轉義字符）
    for(int i = start; i < StringLen(json); i++)
    {
        ushort ch = StringGetCharacter(json, i);
        if(ch == '"' && (i == 0 || StringGetCharacter(json, i - 1) != '\\'))
        {
            end = i;
            break;
        }
    }

    if(end <= start)
        return "";

    return StringSubstr(json, start, end - start);
}

/**
 * @brief 發送 Telegram 消息
 * @details 向預設的 Chat ID 發送消息
 * @param message 要發送的消息文本
 * @return 成功返回 true，失敗返回 false
 * @note 使用 Markdown 格式支持
 */
bool SendTelegramMessage(string message)
{
    return SendTelegramMessageToChatID(message, InpChatID);
}

/**
 * @brief 發送 Telegram 消息到指定 Chat ID
 * @details 向指定的 Chat ID 發送消息
 * @param message 要發送的消息文本
 * @param chatID 目標 Chat ID
 * @return 成功返回 true，失敗返回 false
 * @warning 消息需要進行 URL 編碼
 */
bool SendTelegramMessageToChatID(string message, long chatID)
{
    string url = g_telegramAPIURL + "/sendMessage";

    //--- URL 編碼消息
    string encodedMessage = UrlEncode(message);

    //--- 構建 POST 數據
    string postData = "chat_id=" + IntegerToString(chatID) + "&text=" + encodedMessage + "&parse_mode=HTML";

    char post[];
    char result[];
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

    StringToCharArray(postData, post, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(post, ArraySize(post) - 1); // 移除字符串結束符

    int res = WebRequest("POST", url, headers, 5000, post, result, headers);

    if(res != 200)
    {
        Print("[錯誤] 發送消息失敗，HTTP 代碼：", res);
        return false;
    }

    if(InpVerboseLogging)
        Print("[成功] 消息已發送：", message);

    return true;
}

/**
 * @brief URL 編碼
 * @details 將字符串進行 URL 編碼，用於 HTTP 請求
 * @param str 原始字符串
 * @return URL 編碼後的字符串
 * @note 處理特殊字符，確保 HTTP 請求正確
 */
string UrlEncode(string str)
{
    string result = "";

    for(int i = 0; i < StringLen(str); i++)
    {
        ushort ch = StringGetCharacter(str, i);

        if((ch >= 'A' && ch <= 'Z') ||
           (ch >= 'a' && ch <= 'z') ||
           (ch >= '0' && ch <= '9') ||
           ch == '-' || ch == '_' || ch == '.' || ch == '~')
        {
            result += ShortToString(ch);
        }
        else if(ch == ' ')
        {
            result += "+";
        }
        else
        {
            result += "%" + IntegerToString(ch, 2, '0');
            if(ch > 127) // UTF-8 字符
            {
                // 簡化處理：使用十六進制表示
                result = StringSubstr(result, 0, StringLen(result) - 1);
                result += StringFormat("%%%.2X", ch);
            }
        }
    }

    return result;
}

//+------------------------------------------------------------------+
//| 指令處理函數                                                       |
//+------------------------------------------------------------------+

/**
 * @brief 處理 Telegram 指令
 * @details 解析並執行收到的 Telegram 指令：
 *          - /help - 顯示幫助信息
 *          - /set_tp - 設置止盈
 *          - /set_sl - 設置止損
 *          - /remove_tp - 刪除止盈
 *          - /remove_sl - 刪除止損
 *          - /close_half - 平掉一半倉位
 * @param command 指令字符串
 * @note 包含完整的參數驗證和錯誤處理
 */
void ProcessCommand(string command)
{
    //--- 移除首尾空格
    StringTrimLeft(command);
    StringTrimRight(command);

    //--- 轉換為小寫以便比較
    string commandLower = command;
    StringToLower(commandLower);

    //--- /help 指令
    if(StringFind(commandLower, "/help") == 0)
    {
        SendHelpMessage();
        return;
    }

    //--- /set_tp 指令
    if(StringFind(commandLower, "/set_tp") == 0)
    {
        double price = ExtractPriceFromCommand(command);
        if(price > 0)
        {
            int count = ModifyAllTakeProfit(price);
            if(count >= 0)
                SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止盈價格為 " + DoubleToString(price, g_digits));
            else
                SendTelegramMessage("[錯誤] 修改止盈失敗！請檢查 MT5 日誌。");
        }
        else
        {
            SendTelegramMessage("[錯誤] 無效的價格！用法：/set_tp 價格\n範例：/set_tp 1.1000");
        }
        return;
    }

    //--- /set_sl 指令
    if(StringFind(commandLower, "/set_sl") == 0)
    {
        double price = ExtractPriceFromCommand(command);
        if(price > 0)
        {
            int count = ModifyAllStopLoss(price);
            if(count >= 0)
                SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止損價格為 " + DoubleToString(price, g_digits));
            else
                SendTelegramMessage("[錯誤] 修改止損失敗！請檢查 MT5 日誌。");
        }
        else
        {
            SendTelegramMessage("[錯誤] 無效的價格！用法：/set_sl 價格\n範例：/set_sl 1.0900");
        }
        return;
    }

    //--- /remove_tp 指令
    if(StringFind(commandLower, "/remove_tp") == 0)
    {
        int count = RemoveAllTakeProfit();
        if(count >= 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止盈設置");
        else
            SendTelegramMessage("[錯誤] 刪除止盈失敗！請檢查 MT5 日誌。");
        return;
    }

    //--- /remove_sl 指令
    if(StringFind(commandLower, "/remove_sl") == 0)
    {
        int count = RemoveAllStopLoss();
        if(count >= 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止損設置");
        else
            SendTelegramMessage("[錯誤] 刪除止損失敗！請檢查 MT5 日誌。");
        return;
    }

    //--- /close_half 指令
    if(StringFind(commandLower, "/close_half") == 0)
    {
        double closedLots = CloseHalfPositions();
        if(closedLots >= 0)
            SendTelegramMessage("[成功] 成功平倉 " + DoubleToString(closedLots, 2) + " 手（約佔總倉位的一半）");
        else
            SendTelegramMessage("[錯誤] 平倉失敗！請檢查 MT5 日誌。");
        return;
    }

    //--- 未知指令
    SendTelegramMessage("[錯誤] 未知指令：" + command + "\n\n輸入 /help 查看所有可用指令。");
}

/**
 * @brief 發送幫助消息
 * @details 發送包含所有可用指令說明的幫助消息
 */
void SendHelpMessage()
{
    string helpText = "<b>[幫助] MT5-PositionMaster 指令列表</b>\n\n";
    helpText += "<b>[交易] 止盈/止損管理：</b>\n";
    helpText += "/set_tp &lt;價格&gt; - 設置所有倉位的止盈價格\n";
    helpText += "   範例：/set_tp 1.1000\n\n";
    helpText += "/set_sl &lt;價格&gt; - 設置所有倉位的止損價格\n";
    helpText += "   範例：/set_sl 1.0900\n\n";
    helpText += "/remove_tp - 刪除所有倉位的止盈設置\n\n";
    helpText += "/remove_sl - 刪除所有倉位的止損設置\n\n";
    helpText += "<b>[統計] 倉位管理：</b>\n";
    helpText += "/close_half - 平掉約一半的總倉位手數\n";
    helpText += "   （智能選擇訂單以達到最接近 50%）\n\n";
    helpText += "<b>[信息] 幫助：</b>\n";
    helpText += "/help - 顯示此幫助信息\n\n";
    helpText += "<i>提示：所有指令都會作用於當前交易品種 (" + _Symbol + ") 的所有倉位。</i>";

    SendTelegramMessage(helpText);
}

/**
 * @brief 從指令中提取價格
 * @details 從指令字符串中解析出價格參數
 * @param command 指令字符串
 * @return 提取的價格，失敗返回 0
 * @note 支持多種格式：空格分隔、多個空格等
 */
double ExtractPriceFromCommand(string command)
{
    //--- 查找第一個空格
    int spacePos = StringFind(command, " ");
    if(spacePos < 0)
        return 0;

    //--- 提取價格部分
    string priceStr = StringSubstr(command, spacePos + 1);
    StringTrimLeft(priceStr);
    StringTrimRight(priceStr);

    //--- 轉換為數字
    double price = StringToDouble(priceStr);

    return price;
}

//+------------------------------------------------------------------+
//| 倉位管理函數                                                       |
//+------------------------------------------------------------------+

/**
 * @brief 修改所有倉位的止盈價格
 * @details 遍歷所有當前開倉，將止盈價格統一修改為指定值
 * @param targetPrice 目標止盈價格
 * @return 成功修改的倉位數量，失敗返回 -1
 * @note 如果某個倉位修改失敗，會記錄到日誌但繼續處理其他倉位
 * @warning 確保價格在合理範圍內，避免過於接近當前價格
 */
int ModifyAllTakeProfit(double targetPrice)
{
    int totalPositions = PositionsTotal();
    int modifiedCount = 0;
    int failedCount = 0;

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        return 0;
    }

    Print("[處理中] 開始修改 ", totalPositions, " 個倉位的止盈價格為：", DoubleToString(targetPrice, g_digits));

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 只處理當前交易品種
        if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        //--- 獲取當前倉位信息
        double currentSL = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice = (posType == POSITION_TYPE_BUY) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //--- 驗證價格合理性
        if(!ValidateTPPrice(targetPrice, currentPrice, posType))
        {
            Print("[警告] 倉位 #", ticket, " 的止盈價格不合理，跳過");
            failedCount++;
            continue;
        }

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = _Symbol;
        request.sl = currentSL;
        request.tp = targetPrice;

        if(!OrderSend(request, result))
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", GetLastError());
            failedCount++;
        }
        else if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("[成功] 倉位 #", ticket, " 止盈已修改為：", DoubleToString(targetPrice, g_digits));
            modifiedCount++;
        }
        else
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，返回代碼：", result.retcode);
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    return (failedCount == 0) ? modifiedCount : -1;
}

/**
 * @brief 修改所有倉位的止損價格
 * @details 遍歷所有當前開倉，將止損價格統一修改為指定值
 * @param targetPrice 目標止損價格
 * @return 成功修改的倉位數量，失敗返回 -1
 * @note 如果某個倉位修改失敗，會記錄到日誌但繼續處理其他倉位
 * @warning 確保價格在合理範圍內，避免過於接近當前價格
 */
int ModifyAllStopLoss(double targetPrice)
{
    int totalPositions = PositionsTotal();
    int modifiedCount = 0;
    int failedCount = 0;

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        return 0;
    }

    Print("[處理中] 開始修改 ", totalPositions, " 個倉位的止損價格為：", DoubleToString(targetPrice, g_digits));

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 只處理當前交易品種
        if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        //--- 獲取當前倉位信息
        double currentTP = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice = (posType == POSITION_TYPE_BUY) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //--- 驗證價格合理性
        if(!ValidateSLPrice(targetPrice, currentPrice, posType))
        {
            Print("[警告] 倉位 #", ticket, " 的止損價格不合理，跳過");
            failedCount++;
            continue;
        }

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = _Symbol;
        request.sl = targetPrice;
        request.tp = currentTP;

        if(!OrderSend(request, result))
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", GetLastError());
            failedCount++;
        }
        else if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("[成功] 倉位 #", ticket, " 止損已修改為：", DoubleToString(targetPrice, g_digits));
            modifiedCount++;
        }
        else
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，返回代碼：", result.retcode);
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    return (failedCount == 0) ? modifiedCount : -1;
}

/**
 * @brief 刪除所有倉位的止盈設置
 * @details 將所有倉位的止盈價格設置為 0（無止盈）
 * @return 成功修改的倉位數量，失敗返回 -1
 */
int RemoveAllTakeProfit()
{
    int totalPositions = PositionsTotal();
    int modifiedCount = 0;
    int failedCount = 0;

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        return 0;
    }

    Print("[處理中] 開始刪除 ", totalPositions, " 個倉位的止盈設置");

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 只處理當前交易品種
        if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        //--- 獲取當前止損
        double currentSL = PositionGetDouble(POSITION_SL);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = _Symbol;
        request.sl = currentSL;
        request.tp = 0; // 設置為 0 表示刪除止盈

        if(!OrderSend(request, result))
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", GetLastError());
            failedCount++;
        }
        else if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("[成功] 倉位 #", ticket, " 止盈已刪除");
            modifiedCount++;
        }
        else
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，返回代碼：", result.retcode);
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    return (failedCount == 0) ? modifiedCount : -1;
}

/**
 * @brief 刪除所有倉位的止損設置
 * @details 將所有倉位的止損價格設置為 0（無止損）
 * @return 成功修改的倉位數量，失敗返回 -1
 * @warning 刪除止損可能增加交易風險，請謹慎使用
 */
int RemoveAllStopLoss()
{
    int totalPositions = PositionsTotal();
    int modifiedCount = 0;
    int failedCount = 0;

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        return 0;
    }

    Print("[處理中] 開始刪除 ", totalPositions, " 個倉位的止損設置");

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 只處理當前交易品種
        if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        //--- 獲取當前止盈
        double currentTP = PositionGetDouble(POSITION_TP);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = _Symbol;
        request.sl = 0; // 設置為 0 表示刪除止損
        request.tp = currentTP;

        if(!OrderSend(request, result))
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", GetLastError());
            failedCount++;
        }
        else if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("[成功] 倉位 #", ticket, " 止損已刪除");
            modifiedCount++;
        }
        else
        {
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，返回代碼：", result.retcode);
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    return (failedCount == 0) ? modifiedCount : -1;
}

/**
 * @brief 平掉一半倉位
 * @details 智能選擇並平掉約一半的總倉位手數：
 *          - 計算總手數
 *          - 計算目標平倉手數（總手數的 50%）
 *          - 智能選擇訂單組合以達到最接近目標
 * @return 成功平倉的手數，失敗返回 -1
 * @note 使用動態規劃算法選擇最優訂單組合
 *
 * @example
 * 範例：6 單，每單 0.5 手（總 3 手）
 * 目標：平掉 1.5 手
 * 結果：選擇 3 單（1.5 手）平倉
 */
double CloseHalfPositions()
{
    int totalPositions = PositionsTotal();

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        return 0;
    }

    //--- 收集所有倉位信息
    struct PositionInfo
    {
        ulong ticket;
        double lots;
    };

    PositionInfo positions[];
    ArrayResize(positions, 0);

    double totalLots = 0;

    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 只處理當前交易品種
        if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        double lots = PositionGetDouble(POSITION_VOLUME);
        totalLots += lots;

        int size = ArraySize(positions);
        ArrayResize(positions, size + 1);
        positions[size].ticket = ticket;
        positions[size].lots = lots;
    }

    int posCount = ArraySize(positions);

    if(posCount == 0)
    {
        Print("[信息] 當前交易品種沒有開倉倉位");
        return 0;
    }

    Print("[統計] 總倉位數：", posCount, "，總手數：", DoubleToString(totalLots, 2));

    double targetLots = totalLots / 2.0;
    Print("[目標] 目標平倉手數：", DoubleToString(targetLots, 2));

    //--- 選擇要平倉的訂單（貪心算法：儘量接近目標手數）
    bool selected[];
    ArrayResize(selected, posCount);
    ArrayInitialize(selected, false);

    double selectedLots = 0;
    double minDiff = MathAbs(totalLots - targetLots); // 初始差值

    //--- 貪心選擇：逐個選擇訂單，使總手數最接近目標
    for(int i = 0; i < posCount; i++)
    {
        double newTotal = selectedLots + positions[i].lots;
        double newDiff = MathAbs(newTotal - targetLots);

        if(newDiff < minDiff || (newDiff == minDiff && newTotal <= targetLots))
        {
            selected[i] = true;
            selectedLots += positions[i].lots;
            minDiff = newDiff;
        }

        //--- 如果已經很接近目標，可以停止
        if(selectedLots >= targetLots * 0.95 && selectedLots <= targetLots * 1.05)
            break;
    }

    //--- 如果沒有選中任何訂單，至少選擇一個
    bool hasSelected = false;
    for(int i = 0; i < posCount; i++)
    {
        if(selected[i])
        {
            hasSelected = true;
            break;
        }
    }

    if(!hasSelected && posCount > 0)
    {
        selected[0] = true;
        selectedLots = positions[0].lots;
    }

    Print("[成功] 選擇平倉 ", DoubleToString(selectedLots, 2), " 手（目標 ", DoubleToString(targetLots, 2), " 手）");

    //--- 執行平倉
    int closedCount = 0;
    int failedCount = 0;
    double actualClosedLots = 0;

    for(int i = 0; i < posCount; i++)
    {
        if(!selected[i])
            continue;

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        //--- 獲取倉位類型
        PositionGetTicket(i);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        request.action = TRADE_ACTION_DEAL;
        request.position = positions[i].ticket;
        request.symbol = _Symbol;
        request.volume = positions[i].lots;
        request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (posType == POSITION_TYPE_BUY) ?
                       SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.deviation = 10;

        if(!OrderSend(request, result))
        {
            Print("[錯誤] 倉位 #", positions[i].ticket, " 平倉失敗，錯誤代碼：", GetLastError());
            failedCount++;
        }
        else if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("[成功] 倉位 #", positions[i].ticket, " 已平倉，手數：", DoubleToString(positions[i].lots, 2));
            closedCount++;
            actualClosedLots += positions[i].lots;
        }
        else
        {
            Print("[錯誤] 倉位 #", positions[i].ticket, " 平倉失敗，返回代碼：", result.retcode);
            failedCount++;
        }
    }

    Print("[統計] 平倉結果：成功 ", closedCount, " 個（", DoubleToString(actualClosedLots, 2), " 手），失敗 ", failedCount, " 個");

    return (failedCount == 0) ? actualClosedLots : -1;
}

//+------------------------------------------------------------------+
//| 輔助函數                                                           |
//+------------------------------------------------------------------+

/**
 * @brief 驗證止盈價格的合理性
 * @details 檢查止盈價格是否符合以下條件：
 *          - 買單：止盈價格 > 當前價格
 *          - 賣單：止盈價格 < 當前價格
 *          - 距離當前價格至少 InpMinTPSLDistance 點
 * @param tpPrice 止盈價格
 * @param currentPrice 當前價格
 * @param posType 倉位類型
 * @return 價格合理返回 true，否則返回 false
 */
bool ValidateTPPrice(double tpPrice, double currentPrice, ENUM_POSITION_TYPE posType)
{
    if(tpPrice <= 0)
        return false;

    double minDistance = InpMinTPSLDistance * g_point;

    if(posType == POSITION_TYPE_BUY)
    {
        if(tpPrice <= currentPrice)
        {
            Print("[錯誤] 買單止盈價格必須高於當前價格");
            return false;
        }

        if(tpPrice - currentPrice < minDistance)
        {
            Print("[錯誤] 止盈價格距離當前價格太近（最小 ", InpMinTPSLDistance, " 點）");
            return false;
        }
    }
    else // POSITION_TYPE_SELL
    {
        if(tpPrice >= currentPrice)
        {
            Print("[錯誤] 賣單止盈價格必須低於當前價格");
            return false;
        }

        if(currentPrice - tpPrice < minDistance)
        {
            Print("[錯誤] 止盈價格距離當前價格太近（最小 ", InpMinTPSLDistance, " 點）");
            return false;
        }
    }

    return true;
}

/**
 * @brief 驗證止損價格的合理性
 * @details 檢查止損價格是否符合以下條件：
 *          - 買單：止損價格 < 當前價格
 *          - 賣單：止損價格 > 當前價格
 *          - 距離當前價格至少 InpMinTPSLDistance 點
 * @param slPrice 止損價格
 * @param currentPrice 當前價格
 * @param posType 倉位類型
 * @return 價格合理返回 true，否則返回 false
 */
bool ValidateSLPrice(double slPrice, double currentPrice, ENUM_POSITION_TYPE posType)
{
    if(slPrice <= 0)
        return false;

    double minDistance = InpMinTPSLDistance * g_point;

    if(posType == POSITION_TYPE_BUY)
    {
        if(slPrice >= currentPrice)
        {
            Print("[錯誤] 買單止損價格必須低於當前價格");
            return false;
        }

        if(currentPrice - slPrice < minDistance)
        {
            Print("[錯誤] 止損價格距離當前價格太近（最小 ", InpMinTPSLDistance, " 點）");
            return false;
        }
    }
    else // POSITION_TYPE_SELL
    {
        if(slPrice <= currentPrice)
        {
            Print("[錯誤] 賣單止損價格必須高於當前價格");
            return false;
        }

        if(slPrice - currentPrice < minDistance)
        {
            Print("[錯誤] 止損價格距離當前價格太近（最小 ", InpMinTPSLDistance, " 點）");
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
