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
input string InpBotToken = "";

/** @brief 授權的 Telegram Chat ID */
input long InpChatID = 0;

/** @brief 輪詢間隔（秒） */
input int InpPollingInterval = 2;                 // 輪詢間隔（秒）

/** @brief 快速模式 - 減少面板重發以提高響應速度 */
input bool InpFastMode = false;                   // 快速模式（減少按鈕延遲）

//+------------------------------------------------------------------+
//| 用戶狀態枚舉                                                        |
//+------------------------------------------------------------------+

/** @brief 用戶交互狀態枚舉 */
enum UserState
{
    STATE_IDLE,           // 空閒狀態
    STATE_WAITING_TP,     // 等待輸入止盈價格
    STATE_WAITING_SL      // 等待輸入止損價格
};

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

/** @brief 最後操作的詳細結果訊息 */
string g_lastOperationResult = "";

/** @brief 用戶當前狀態 */
UserState g_userState = STATE_IDLE;

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

    Print("========================================");
    Print("MT5-PositionMaster EA v1.0.0 已啟動");
    Print("========================================");

    //--- 獲取最新的 update ID，避免處理舊消息
    GetLatestUpdateID();

    //--- 發送啟動通知
    string startMsg = "[成功] MT5-PositionMaster EA 已成功啟動！\n\n";
    startMsg += "[系統] EA 版本：1.0.0\n";
    startMsg += "[時間] 輪詢間隔：" + IntegerToString(InpPollingInterval) + " 秒\n\n";
    startMsg += "輸入 /help 查看所有可用指令。";

    SendTelegramMessage(startMsg);

    Print("[成功] MT5-PositionMaster EA 初始化成功！");
    Print("[時間] 輪詢間隔：", InpPollingInterval, " 秒");
    Print("[調試] g_isInitialized 已設置為: true");

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

    //--- 獲取原因說明
    string reasonText = "";

    switch(reason)
    {
        case REASON_PROGRAM:
            reasonText = "EA 正常終止";
            break;
        case REASON_REMOVE:
            reasonText = "EA 被從圖表移除";
            break;
        case REASON_RECOMPILE:
            reasonText = "EA 被重新編譯（將自動重啟）";
            break;
        case REASON_CHARTCHANGE:
            reasonText = "圖表品種或週期改變（將自動重啟）";
            break;
        case REASON_CHARTCLOSE:
            reasonText = "圖表關閉";
            break;
        case REASON_PARAMETERS:
            reasonText = "輸入參數改變（將自動重啟）";
            break;
        case REASON_ACCOUNT:
            reasonText = "帳戶切換（將自動重啟）";
            break;
        case REASON_TEMPLATE:
            reasonText = "應用新模板（將自動重啟）";
            break;
        case REASON_INITFAILED:
            reasonText = "初始化失敗";
            break;
        case REASON_CLOSE:
            reasonText = "終端關閉";
            break;
        default:
            reasonText = "未知原因";
            break;
    }

    //--- 發送關閉通知（所有情況都發送）
    string msg = "MT5-PositionMaster EA 已停止\n\n";
    msg += "原因代碼：" + IntegerToString(reason) + "\n";
    msg += "說明：" + reasonText;
    SendTelegramMessage(msg);

    //--- 記錄日誌
    Print("[信息] MT5-PositionMaster EA 已停止，原因：", reasonText, " (代碼:", reason, ")");
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
    // 方法：使用 offset=-1 獲取最新的一條更新，然後立即確認它
    // 這樣可以跳過所有舊消息

    string url = g_telegramAPIURL + "/getUpdates?offset=-1&limit=1";
    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultString;
    int timeout = 5000;

    int res = WebRequest("GET", url, headers, timeout, post, result, headers);

    if(res == 200)
    {
        resultString = CharArrayToString(result);

        //--- 查找最新的 update_id
        int start = StringFind(resultString, "\"update_id\":");
        if(start >= 0)
        {
            start += 13; // 長度 "\"update_id\":"
            int end = StringFind(resultString, ",", start);
            if(end < 0)
                end = StringFind(resultString, "}", start);

            if(end > start)
            {
                string updateIDStr = StringSubstr(resultString, start, end - start);
                g_lastUpdateID = StringToInteger(updateIDStr);

                // 立即確認這條消息（使用 offset = update_id + 1）
                // 這會告訴 Telegram 清除所有 <= update_id 的舊消息
                string confirmUrl = g_telegramAPIURL + "/getUpdates?offset=" + IntegerToString(g_lastUpdateID + 1) + "&limit=1";
                char confirmResult[];
                WebRequest("GET", confirmUrl, headers, timeout, post, confirmResult, headers);
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
    // 明確指定要接收 message 和 callback_query 更新
    string url = g_telegramAPIURL + "/getUpdates?offset=" + IntegerToString(g_lastUpdateID + 1) +
                 "&timeout=5&allowed_updates=[\"message\",\"callback_query\"]";
    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultString;
    int timeout = 7000; // 7秒超時（5秒長輪詢 + 2秒緩衝）

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

    //--- 解析 JSON 響應
    if(StringFind(resultString, "\"ok\":true") < 0)
    {
        Print("[錯誤] Telegram API 響應錯誤");
        return false;
    }

    //--- 提取 result 數組

    int resultStart = StringFind(resultString, "\"result\":[");

    if(resultStart < 0)
        return true; // 沒有新消息

    // 找到 [ 的位置（在 "result":[ 中）
    int bracketStart = resultStart + 9;  // "result": 有 9 個字符
    resultStart = bracketStart + 1;  // 數組內容從 [ 之後開始

    //--- 使用括號計數法找到 result 數組的真正結束位置
    int bracketCount = 0;
    int resultEnd = -1;
    bool inString = false;

    for(int i = bracketStart; i < StringLen(resultString); i++)
    {
        ushort ch = StringGetCharacter(resultString, i);

        // 處理字符串內的引號
        if(ch == '"')
        {
            // 計算前面連續的反斜杠數量
            int backslashCount = 0;
            int j = i - 1;
            while(j >= 0 && StringGetCharacter(resultString, j) == '\\')
            {
                backslashCount++;
                j--;
            }

            // 偶數個反斜杠（包括0）意味著引號不是轉義的
            if(backslashCount % 2 == 0)
                inString = !inString;
        }

        if(!inString)
        {
            if(ch == '[')
                bracketCount++;
            else if(ch == ']')
            {
                bracketCount--;
                if(bracketCount == 0)
                {
                    resultEnd = i;
                    break;
                }
            }
        }
    }

    if(resultEnd < 0 || resultEnd <= resultStart)
        return true; // 空結果或解析失敗

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
        //--- 查找下一個 { 開始符
        int updateStart = StringFind(updates, "{", pos);
        if(updateStart < 0)
            break;

        //--- 查找對應的 } 結束位置（使用括號計數）
        int braceCount = 0;
        int updateEnd = -1;
        bool inString = false;

        for(int i = updateStart; i < StringLen(updates); i++)
        {
            ushort ch = StringGetCharacter(updates, i);

            // 處理字符串內的引號（正確處理轉義字符，包括連續的反斜杠）
            if(ch == '"')
            {
                // 計算前面有多少個連續的反斜杠
                int backslashCount = 0;
                int j = i - 1;
                while(j >= 0 && StringGetCharacter(updates, j) == '\\')
                {
                    backslashCount++;
                    j--;
                }

                // 如果反斜杠數量是偶數（包括 0），則這個引號不是轉義的
                if(backslashCount % 2 == 0)
                    inString = !inString;
            }

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
 *          - 提取並處理指令或按鈕回調
 * @param update JSON 格式的單個更新字符串
 * @note 包含完整的安全驗證機制，支持 message 和 callback_query
 */
void ProcessSingleUpdate(string update)
{
    //--- 提取 update_id
    long updateID = ExtractUpdateID(update);
    if(updateID <= g_lastUpdateID)
        return; // 已處理過的消息

    g_lastUpdateID = updateID;

    //--- 檢查是否為 callback_query（按鈕點擊）
    if(StringFind(update, "\"callback_query\"") >= 0)
    {
        //--- 提取 callback_query_id
        string callbackQueryID = ExtractCallbackQueryID(update);
        if(StringLen(callbackQueryID) == 0)
            return;

        //--- 提取 callback_data
        string callbackData = ExtractCallbackData(update);
        if(StringLen(callbackData) == 0)
            return;

        //--- 提取並驗證 chat_id（在 callback_query.message.chat.id 中）
        long chatID = ExtractChatID(update);
        if(chatID != InpChatID)
        {
            Print("[警告] 未授權的 Chat ID 嘗試訪問（callback_query）：", chatID);
            AnswerCallbackQuery(callbackQueryID, "未授權訪問");
            return;
        }

        //--- 處理按鈕回調
        ProcessCallbackQuery(callbackData, callbackQueryID);
        return;
    }

    //--- 處理普通消息
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
    // 查找 "chat" 字段
    int start = StringFind(json, "\"chat\"");
    if(start < 0)
        return 0;

    // 從 "chat" 之後查找 "id"
    start = StringFind(json, "\"id\"", start);
    if(start < 0)
        return 0;

    // 找到 "id": 之後的數字開始位置
    start = StringFind(json, ":", start);
    if(start < 0)
        return 0;

    start++; // 跳過冒號

    // 跳過空格
    while(start < StringLen(json))
    {
        ushort ch = StringGetCharacter(json, start);
        if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r')
            break;
        start++;
    }

    // 查找數字結束位置
    int end = start;
    while(end < StringLen(json))
    {
        ushort ch = StringGetCharacter(json, end);
        // 數字、負號、或空格以外的字符表示結束
        if(ch != '-' && ch != '+' && (ch < '0' || ch > '9'))
            break;
        end++;
    }

    if(end <= start)
        return 0;

    string idStr = StringSubstr(json, start, end - start);
    StringTrimLeft(idStr);
    StringTrimRight(idStr);

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
 * @brief 提取 Callback Query ID
 * @details 從 JSON 字符串中提取 callback_query.id 字段
 * @param json JSON 格式字符串
 * @return Callback Query ID，失敗返回空字符串
 */
string ExtractCallbackQueryID(string json)
{
    //--- 查找 "callback_query" 字段
    int start = StringFind(json, "\"callback_query\"");
    if(start < 0)
        return "";

    //--- 從 "callback_query" 之後查找 "id"
    start = StringFind(json, "\"id\":\"", start);
    if(start < 0)
        return "";

    start += 6; // 跳過 "id":"
    int end = StringFind(json, "\"", start);

    if(end <= start)
        return "";

    return StringSubstr(json, start, end - start);
}

/**
 * @brief 提取 Callback Data
 * @details 從 JSON 字符串中提取 callback_query.data 字段
 * @param json JSON 格式字符串
 * @return Callback Data，失敗返回空字符串
 */
string ExtractCallbackData(string json)
{
    //--- 查找 "data" 字段（在 callback_query 中）
    int start = StringFind(json, "\"callback_query\"");
    if(start < 0)
        return "";

    //--- 從 "callback_query" 之後查找 "data"
    start = StringFind(json, "\"data\":\"", start);
    if(start < 0)
        return "";

    start += 8; // 跳過 "data":"
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

    int res = WebRequest("POST", url, headers, 2000, post, result, headers);

    if(res != 200)
    {
        Print("[錯誤] 發送消息失敗，HTTP 代碼：", res);
        return false;
    }

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
    uchar bytes[];

    // 將字符串轉換為 UTF-8 字節數組
    int len = StringToCharArray(str, bytes, 0, WHOLE_ARRAY, CP_UTF8);
    if(len > 0)
        len--; // 移除字符串結束符

    for(int i = 0; i < len; i++)
    {
        uchar ch = bytes[i];

        // 不需要編碼的字符（RFC 3986）
        if((ch >= 'A' && ch <= 'Z') ||
           (ch >= 'a' && ch <= 'z') ||
           (ch >= '0' && ch <= '9') ||
           ch == '-' || ch == '_' || ch == '.' || ch == '~')
        {
            result += CharToString(ch);
        }
        else if(ch == ' ')
        {
            result += "+";
        }
        else
        {
            // 使用正確的十六進制格式（大寫）
            result += StringFormat("%%%02X", ch);
        }
    }

    return result;
}

/**
 * @brief 發送帶有 Inline Keyboard 的 Telegram 消息
 * @details 向默認 Chat ID 發送帶有內聯鍵盤按鈕的消息
 * @param message 要發送的消息文本
 * @param inlineKeyboard Inline Keyboard JSON 字符串（格式：[[{...}, {...}], [...]]）
 * @return 成功返回 true，失敗返回 false
 * @note inlineKeyboard 應該是有效的 JSON 數組格式
 */
bool SendTelegramMessageWithKeyboard(string message, string inlineKeyboard)
{
    string url = g_telegramAPIURL + "/sendMessage";

    //--- URL 編碼消息
    string encodedMessage = UrlEncode(message);

    //--- 構建 reply_markup JSON
    string replyMarkup = "{\"inline_keyboard\":" + inlineKeyboard + "}";
    string encodedReplyMarkup = UrlEncode(replyMarkup);

    //--- 構建 POST 數據
    string postData = "chat_id=" + IntegerToString(InpChatID) +
                      "&text=" + encodedMessage +
                      "&parse_mode=HTML" +
                      "&reply_markup=" + encodedReplyMarkup;

    char post[];
    char result[];
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

    StringToCharArray(postData, post, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(post, ArraySize(post) - 1);

    int res = WebRequest("POST", url, headers, 2000, post, result, headers);

    if(res != 200)
    {
        Print("[錯誤] 發送帶按鈕的消息失敗，HTTP 代碼：", res);
        return false;
    }

    return true;
}

/**
 * @brief 回應 Callback Query
 * @details 必須調用此函數來回應用戶的按鈕點擊，否則按鈕會持續顯示加載狀態
 * @param callbackQueryID Callback Query ID
 * @param text 可選的通知文本（顯示在屏幕頂部）
 * @return 成功返回 true，失敗返回 false
 * @note 即使不需要顯示通知，也必須調用此函數
 */
bool AnswerCallbackQuery(string callbackQueryID, string text = "")
{
    string url = g_telegramAPIURL + "/answerCallbackQuery";

    //--- 構建 POST 數據
    string postData = "callback_query_id=" + callbackQueryID;
    if(StringLen(text) > 0)
    {
        postData += "&text=" + UrlEncode(text);
    }

    char post[];
    char result[];
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

    StringToCharArray(postData, post, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(post, ArraySize(post) - 1);

    int res = WebRequest("POST", url, headers, 2000, post, result, headers);

    if(res != 200)
    {
        Print("[錯誤] 回應 Callback Query 失敗，HTTP 代碼：", res);
        return false;
    }

    return true;
}

/**
 * @brief 發送操作菜單面板
 * @details 發送包含所有操作按鈕的 Inline Keyboard 面板
 * @return 成功返回 true，失敗返回 false
 * @note 面板包含：平倉一半、平掉全部、設置TP/SL、刪除TP/SL
 */
bool SendMenuPanel()
{
    //--- 構建按鈕 JSON（使用繁體中文）
    string buttons = "[[" +
        "{\"text\":\"✂️ 平倉一半\", \"callback_data\":\"CH\"}," +
        "{\"text\":\"🚫 平掉全部\", \"callback_data\":\"CA\"}" +
        "],[" +
        "{\"text\":\"🎯 設置TP\", \"callback_data\":\"SETTP\"}," +
        "{\"text\":\"🛡️ 設置SL\", \"callback_data\":\"SETSL\"}" +
        "],[" +
        "{\"text\":\"❌ 刪除TP\", \"callback_data\":\"RTP\"}," +
        "{\"text\":\"❌ 刪除SL\", \"callback_data\":\"RSL\"}" +
        "]]";

    string message = "📋 <b>倉位管理面板</b>\n\n" +
                     "請選擇要執行的操作：";

    return SendTelegramMessageWithKeyboard(message, buttons);
}

/**
 * @brief 處理 Callback Query（按鈕點擊）
 * @details 處理用戶點擊 Inline Keyboard 按鈕的回調
 * @param callbackData 按鈕的 callback_data 值
 * @param callbackQueryID Callback Query ID（用於回應）
 * @note 根據不同的 callback_data 執行相應操作
 */
void ProcessCallbackQuery(string callbackData, string callbackQueryID)
{
    Print("[DEBUG] 收到 Callback Query: ", callbackData);

    //--- 立即回應 callback query（避免按鈕持續加載）
    AnswerCallbackQuery(callbackQueryID);

    //--- 如果用戶點擊了其他操作按鈕（非設置TP/SL），自動取消等待輸入狀態
    if(g_userState != STATE_IDLE && callbackData != "SETTP" && callbackData != "SETSL")
    {
        Print("[DEBUG] 自動取消等待輸入狀態，執行新操作：", callbackData);
        g_userState = STATE_IDLE;
    }

    //--- 根據按鈕 ID 執行相應操作
    if(callbackData == "CH")
    {
        //--- 平倉一半
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel(); // 重新發送面板
            return;
        }
        if(totalPos == 1)
        {
            SendTelegramMessage("[信息] 只有1個倉位，不執行平倉操作");
            SendMenuPanel();
            return;
        }

        double closedLots = CloseHalfPositions();
        if(closedLots > 0)
            SendTelegramMessage("[成功] 成功平倉 " + DoubleToString(closedLots, 2) + " 手（約佔總倉位的一半）\n\n" + g_lastOperationResult);
        else if(closedLots == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 平倉失敗\n\n" + g_lastOperationResult);

        if(!InpFastMode)
            SendMenuPanel(); // 重新發送面板（快速模式下跳過）
    }
    else if(callbackData == "CA")
    {
        //--- 平掉全部
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel();
            return;
        }

        double closedLots = CloseAllPositions();
        if(closedLots > 0)
            SendTelegramMessage("[成功] 成功平掉所有倉位，共 " + DoubleToString(closedLots, 2) + " 手\n\n" + g_lastOperationResult);
        else if(closedLots == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 平倉失敗\n\n" + g_lastOperationResult);

        if(!InpFastMode)
            SendMenuPanel();
    }
    else if(callbackData == "SETTP")
    {
        //--- 設置止盈 - 先檢查是否有倉位
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            if(!InpFastMode)
                SendMenuPanel();
            return;
        }

        //--- 有倉位，進入等待輸入狀態
        g_userState = STATE_WAITING_TP;
        SendTelegramMessage("🎯 請輸入止盈價格（純數字）：\n\n例如：2050.50\n\n輸入 cancel 可取消操作");
        // 不重新發送面板，等待用戶輸入
    }
    else if(callbackData == "SETSL")
    {
        //--- 設置止損 - 先檢查是否有倉位
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            if(!InpFastMode)
                SendMenuPanel();
            return;
        }

        //--- 有倉位，進入等待輸入狀態
        g_userState = STATE_WAITING_SL;
        SendTelegramMessage("🛡️ 請輸入止損價格（純數字）：\n\n例如：2040.30\n\n輸入 cancel 可取消操作");
        // 不重新發送面板，等待用戶輸入
    }
    else if(callbackData == "RTP")
    {
        //--- 刪除止盈
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel();
            return;
        }

        int count = RemoveAllTakeProfit();
        if(count > 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止盈設置\n\n" + g_lastOperationResult);
        else if(count == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 刪除止盈失敗\n\n" + g_lastOperationResult);

        if(!InpFastMode)
            SendMenuPanel();
    }
    else if(callbackData == "RSL")
    {
        //--- 刪除止損
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel();
            return;
        }

        int count = RemoveAllStopLoss();
        if(count > 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止損設置\n\n" + g_lastOperationResult);
        else if(count == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 刪除止損失敗\n\n" + g_lastOperationResult);

        if(!InpFastMode)
            SendMenuPanel();
    }
    else
    {
        SendTelegramMessage("[錯誤] 未知的按鈕操作：" + callbackData);
        SendMenuPanel();
    }
}

//+------------------------------------------------------------------+
//| 指令處理函數                                                       |
//+------------------------------------------------------------------+

/**
 * @brief 處理 Telegram 指令
 * @details 解析並執行收到的 Telegram 指令：
 *          - /help - 顯示幫助信息
 *          - /menu - 顯示操作面板
 *          - /settp - 設置止盈
 *          - /setsl - 設置止損
 *          - /rtp - 刪除止盈
 *          - /rsl - 刪除止損
 *          - /ch - 平掉一半倉位
 *          - /ca - 平掉所有倉位
 * @param command 指令字符串或用戶輸入
 * @note 包含完整的參數驗證和錯誤處理，支持狀態機邏輯
 */
void ProcessCommand(string command)
{
    //--- 移除首尾空格
    StringTrimLeft(command);
    StringTrimRight(command);

    if(StringLen(command) == 0)
        return;

    //--- 檢查用戶是否處於等待輸入狀態
    if(g_userState != STATE_IDLE)
    {
        //--- 先檢查是否為取消指令（支持 /cancel 或 cancel）
        string commandLowerTemp = command;
        StringToLower(commandLowerTemp);
        StringTrimLeft(commandLowerTemp);
        StringTrimRight(commandLowerTemp);

        if(commandLowerTemp == "cancel" || commandLowerTemp == "/cancel")
        {
            //--- 取消操作，重置狀態
            g_userState = STATE_IDLE;
            SendTelegramMessage("[信息] 操作已取消");
            SendMenuPanel();
            return;
        }

        //--- 檢查是否為純數字輸入
        double price = StringToDouble(command);

        // 驗證是否為有效數字（大於0或包含小數點）
        bool isValidNumber = (price > 0) || (StringFind(command, ".") >= 0);

        if(isValidNumber && price > 0)
        {
            //--- 根據狀態執行相應操作
            if(g_userState == STATE_WAITING_TP)
            {
                //--- 設置止盈
                int count = ModifyAllTakeProfit(price);
                if(count > 0)
                    SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止盈價格為 " + DoubleToString(price, g_digits) + "\n\n" + g_lastOperationResult);
                else if(count == 0)
                    SendTelegramMessage("[信息] 當前沒有開倉倉位");
                else
                    SendTelegramMessage("[錯誤] 修改止盈失敗\n\n" + g_lastOperationResult);

                //--- 重置狀態並重新發送面板
                g_userState = STATE_IDLE;
                SendMenuPanel();
                return;
            }
            else if(g_userState == STATE_WAITING_SL)
            {
                //--- 設置止損
                int count = ModifyAllStopLoss(price);
                if(count > 0)
                    SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止損價格為 " + DoubleToString(price, g_digits) + "\n\n" + g_lastOperationResult);
                else if(count == 0)
                    SendTelegramMessage("[信息] 當前沒有開倉倉位");
                else
                    SendTelegramMessage("[錯誤] 修改止損失敗\n\n" + g_lastOperationResult);

                //--- 重置狀態並重新發送面板
                g_userState = STATE_IDLE;
                SendMenuPanel();
                return;
            }
        }
        else
        {
            //--- 無效的數字輸入
            SendTelegramMessage("[錯誤] 無效的價格！請輸入有效的數字，例如：2050.50\n\n或輸入 cancel 取消操作");
            return;
        }
    }

    //--- 只處理以 / 開頭的指令，其他消息忽略
    if(StringGetCharacter(command, 0) != '/')
    {
        return;  // 不是指令，直接返回，不處理
    }

    //--- 轉換為小寫以便比較
    string commandLower = command;
    StringToLower(commandLower);

    //--- /help 指令
    if(StringFind(commandLower, "/help") == 0)
    {
        SendHelpMessage();
        return;
    }

    //--- /menu 指令
    if(StringFind(commandLower, "/menu") == 0)
    {
        SendMenuPanel();
        return;
    }

    //--- /cancel 指令 - 取消當前狀態
    if(StringFind(commandLower, "/cancel") == 0)
    {
        if(g_userState != STATE_IDLE)
        {
            g_userState = STATE_IDLE;
            SendTelegramMessage("[信息] 操作已取消");
            SendMenuPanel();
        }
        else
        {
            SendTelegramMessage("[信息] 當前沒有進行中的操作");
        }
        return;
    }

    //--- /settp 指令
    if(StringFind(commandLower, "/settp") == 0)
    {
        double price = ExtractPriceFromCommand(command);
        if(price > 0)
        {
            int count = ModifyAllTakeProfit(price);
            if(count > 0)
                SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止盈價格為 " + DoubleToString(price, g_digits) + "\n\n" + g_lastOperationResult);
            else if(count == 0)
                SendTelegramMessage("[信息] 當前沒有開倉倉位");
            else
                SendTelegramMessage("[錯誤] 修改止盈失敗\n\n" + g_lastOperationResult);
        }
        else
        {
            SendTelegramMessage("[錯誤] 無效的價格！用法：/settp 價格\n範例：/settp 1.1000");
        }
        SendMenuPanel(); // 重新發送面板
        return;
    }

    //--- /setsl 指令
    if(StringFind(commandLower, "/setsl") == 0)
    {
        double price = ExtractPriceFromCommand(command);
        if(price > 0)
        {
            int count = ModifyAllStopLoss(price);
            if(count > 0)
                SendTelegramMessage("[成功] 成功修改 " + IntegerToString(count) + " 個倉位的止損價格為 " + DoubleToString(price, g_digits) + "\n\n" + g_lastOperationResult);
            else if(count == 0)
                SendTelegramMessage("[信息] 當前沒有開倉倉位");
            else
                SendTelegramMessage("[錯誤] 修改止損失敗\n\n" + g_lastOperationResult);
        }
        else
        {
            SendTelegramMessage("[錯誤] 無效的價格！用法：/setsl 價格\n範例：/setsl 1.0900");
        }
        SendMenuPanel(); // 重新發送面板
        return;
    }

    //--- /rtp 指令
    if(StringFind(commandLower, "/rtp") == 0)
    {
        int count = RemoveAllTakeProfit();
        if(count > 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止盈設置\n\n" + g_lastOperationResult);
        else if(count == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 刪除止盈失敗\n\n" + g_lastOperationResult);
        SendMenuPanel(); // 重新發送面板
        return;
    }

    //--- /rsl 指令
    if(StringFind(commandLower, "/rsl") == 0)
    {
        int count = RemoveAllStopLoss();
        if(count > 0)
            SendTelegramMessage("[成功] 成功刪除 " + IntegerToString(count) + " 個倉位的止損設置\n\n" + g_lastOperationResult);
        else if(count == 0)
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
        else
            SendTelegramMessage("[錯誤] 刪除止損失敗\n\n" + g_lastOperationResult);
        SendMenuPanel(); // 重新發送面板
        return;
    }

    //--- /ch 指令
    if(StringFind(commandLower, "/ch") == 0)
    {
        //--- 先檢查倉位數量
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel(); // 重新發送面板
            return;
        }

        if(totalPos == 1)
        {
            SendTelegramMessage("[信息] 只有1個倉位，不執行平倉操作");
            SendMenuPanel(); // 重新發送面板
            return;
        }

        //--- 執行平倉
        double closedLots = CloseHalfPositions();
        if(closedLots > 0)
            SendTelegramMessage("[成功] 成功平倉 " + DoubleToString(closedLots, 2) + " 手（約佔總倉位的一半）\n\n" + g_lastOperationResult);
        else
            SendTelegramMessage("[錯誤] 平倉失敗\n\n" + g_lastOperationResult);
        SendMenuPanel(); // 重新發送面板
        return;
    }

    //--- /ca 指令
    if(StringFind(commandLower, "/ca") == 0)
    {
        //--- 先檢查倉位數量
        int totalPos = PositionsTotal();
        if(totalPos == 0)
        {
            SendTelegramMessage("[信息] 當前沒有開倉倉位");
            SendMenuPanel(); // 重新發送面板
            return;
        }

        //--- 執行平倉
        double closedLots = CloseAllPositions();
        if(closedLots > 0)
            SendTelegramMessage("[成功] 成功平倉所有倉位，共 " + DoubleToString(closedLots, 2) + " 手\n\n" + g_lastOperationResult);
        else
            SendTelegramMessage("[錯誤] 平倉失敗\n\n" + g_lastOperationResult);
        SendMenuPanel(); // 重新發送面板
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
    string helpText = "<b>📖 [幫助] MT5-PositionMaster 指令列表</b>\n\n";

    helpText += "<b>🎮 快速操作面板：</b>\n";
    helpText += "/menu - 顯示操作按鈕面板（推薦使用）\n";
    helpText += "   使用按鈕可快速執行操作，無需輸入指令\n\n";

    helpText += "<b>📝 交易指令（止盈/止損管理）：</b>\n";
    helpText += "/settp &lt;價格&gt; - 設置所有倉位的止盈價格\n";
    helpText += "   範例：/settp 1.1000\n\n";
    helpText += "/setsl &lt;價格&gt; - 設置所有倉位的止損價格\n";
    helpText += "   範例：/setsl 1.0900\n\n";
    helpText += "/rtp - 刪除所有倉位的止盈設置\n\n";
    helpText += "/rsl - 刪除所有倉位的止損設置\n\n";

    helpText += "<b>📊 倉位管理：</b>\n";
    helpText += "/ch - 平掉約一半的總倉位手數\n";
    helpText += "   （智能選擇訂單以達到最接近 50%）\n\n";
    helpText += "/ca - 平掉所有倉位\n\n";

    helpText += "<b>ℹ️ 其他指令：</b>\n";
    helpText += "/help - 顯示此幫助信息\n";
    helpText += "/cancel 或 cancel - 取消當前操作\n\n";

    helpText += "<i>💡 提示：</i>\n";
    helpText += "<i>• 所有指令都會作用於所有交易品種的所有倉位</i>\n";
    helpText += "<i>• 點擊按鈕設置 TP/SL 時，直接輸入數字即可</i>\n";
    helpText += "<i>• 等待輸入時，輸入 cancel 可隨時取消</i>\n";
    helpText += "<i>• 操作完成後會自動顯示操作面板</i>";

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
    string errorDetails = "";

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[處理中] 開始修改 ", totalPositions, " 個倉位的止盈價格為：", DoubleToString(targetPrice, g_digits));

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 獲取當前倉位信息
        double currentSL = PositionGetDouble(POSITION_SL);
        string symbol = PositionGetString(POSITION_SYMBOL);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = currentSL;
        request.tp = targetPrice;

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(modifiedCount) + " 個，失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

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
    string errorDetails = "";

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[處理中] 開始修改 ", totalPositions, " 個倉位的止損價格為：", DoubleToString(targetPrice, g_digits));

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 獲取當前倉位信息
        double currentTP = PositionGetDouble(POSITION_TP);
        string symbol = PositionGetString(POSITION_SYMBOL);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = targetPrice;
        request.tp = currentTP;

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(modifiedCount) + " 個，失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

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
    string errorDetails = "";

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[處理中] 開始刪除 ", totalPositions, " 個倉位的止盈設置");

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 獲取當前止損
        double currentSL = PositionGetDouble(POSITION_SL);
        string symbol = PositionGetString(POSITION_SYMBOL);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = currentSL;
        request.tp = 0; // 設置為 0 表示刪除止盈

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(modifiedCount) + " 個，失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

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
    string errorDetails = "";

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[處理中] 開始刪除 ", totalPositions, " 個倉位的止損設置");

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
            continue;

        //--- 獲取當前止盈
        double currentTP = PositionGetDouble(POSITION_TP);
        string symbol = PositionGetString(POSITION_SYMBOL);

        //--- 修改倉位
        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = symbol;
        request.sl = 0; // 設置為 0 表示刪除止損
        request.tp = currentTP;

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", ticket, " 修改失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(ticket) + " (" + symbol + ") 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 修改結果：成功 ", modifiedCount, " 個，失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(modifiedCount) + " 個，失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

    return (failedCount == 0) ? modifiedCount : -1;
}

/**
 * @brief 平掉所有倉位
 * @details 關閉所有開倉倉位
 * @return 成功平倉的手數，失敗返回 -1
 */
double CloseAllPositions()
{
    int totalPositions = PositionsTotal();

    if(totalPositions == 0)
    {
        Print("[信息] 當前沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[處理中] 開始平倉所有倉位，共 ", totalPositions, " 個");

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
        Print("[信息] 沒有開倉倉位");
        g_lastOperationResult = "";
        return 0;
    }

    Print("[統計] 總倉位數：", posCount, "，總手數：", DoubleToString(totalLots, 2));

    //--- 執行平倉
    int closedCount = 0;
    int failedCount = 0;
    double actualClosedLots = 0;
    string errorDetails = "";

    for(int i = 0; i < posCount; i++)
    {
        //--- 獲取倉位信息
        if(!PositionSelectByTicket(positions[i].ticket))
            continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_DEAL;
        request.position = positions[i].ticket;
        request.symbol = symbol;
        request.volume = positions[i].lots;
        request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (posType == POSITION_TYPE_BUY) ?
                       SymbolInfoDouble(symbol, SYMBOL_BID) :
                       SymbolInfoDouble(symbol, SYMBOL_ASK);
        request.deviation = 10;

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", positions[i].ticket, " 平倉失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(positions[i].ticket) + " (" + symbol + ", " + DoubleToString(positions[i].lots, 2) + "手) 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(positions[i].ticket) + " (" + symbol + ", " + DoubleToString(positions[i].lots, 2) + "手) 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 平倉結果：成功 ", closedCount, " 個（", DoubleToString(actualClosedLots, 2), " 手），失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(closedCount) + " 個（" + DoubleToString(actualClosedLots, 2) + "手），失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

    return (failedCount == 0) ? actualClosedLots : -1;
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
        Print("[信息] 沒有開倉倉位");
        return 0;
    }

    //--- 如果只有1單，不執行平倉
    if(posCount == 1)
    {
        Print("[信息] 只有1個倉位，不執行平倉操作");
        return 0;
    }

    Print("[統計] 總倉位數：", posCount, "，總手數：", DoubleToString(totalLots, 2));

    double targetLots = totalLots / 2.0;
    Print("[目標] 目標平倉手數：", DoubleToString(targetLots, 2));

    //--- 選擇要平倉的訂單（貪心算法：儘量接近目標手數，傾向多平）
    bool selected[];
    ArrayResize(selected, posCount);
    ArrayInitialize(selected, false);

    double selectedLots = 0;
    double minDiff = MathAbs(totalLots - targetLots); // 初始差值

    //--- 貪心選擇：逐個選擇訂單，使總手數最接近目標（寧可多平）
    for(int i = 0; i < posCount; i++)
    {
        double newTotal = selectedLots + positions[i].lots;
        double newDiff = MathAbs(newTotal - targetLots);

        //--- 如果新差值更小或相等，就選擇（傾向多平）
        if(newDiff <= minDiff)
        {
            selected[i] = true;
            selectedLots += positions[i].lots;
            minDiff = newDiff;
        }

        //--- 如果已經很接近目標，可以停止
        if(selectedLots >= targetLots * 0.95 && selectedLots <= targetLots * 1.05)
            break;
    }

    //--- 確保至少選擇一個訂單（但不會全平，因為前面已檢查只有1單的情況）
    bool hasSelected = false;
    for(int i = 0; i < posCount; i++)
    {
        if(selected[i])
        {
            hasSelected = true;
            break;
        }
    }

    if(!hasSelected && posCount > 1)
    {
        selected[0] = true;
        selectedLots = positions[0].lots;
    }

    Print("[成功] 選擇平倉 ", DoubleToString(selectedLots, 2), " 手（目標 ", DoubleToString(targetLots, 2), " 手）");

    //--- 執行平倉
    int closedCount = 0;
    int failedCount = 0;
    double actualClosedLots = 0;
    string errorDetails = "";

    for(int i = 0; i < posCount; i++)
    {
        if(!selected[i])
            continue;

        //--- 獲取倉位信息
        if(!PositionSelectByTicket(positions[i].ticket))
            continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_DEAL;
        request.position = positions[i].ticket;
        request.symbol = symbol;
        request.volume = positions[i].lots;
        request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (posType == POSITION_TYPE_BUY) ?
                       SymbolInfoDouble(symbol, SYMBOL_BID) :
                       SymbolInfoDouble(symbol, SYMBOL_ASK);
        request.deviation = 10;

        if(!OrderSend(request, result))
        {
            int errCode = GetLastError();
            Print("[錯誤] 倉位 #", positions[i].ticket, " 平倉失敗，錯誤代碼：", errCode);
            errorDetails += "\n• 倉位 #" + IntegerToString(positions[i].ticket) + " (" + symbol + ", " + DoubleToString(positions[i].lots, 2) + "手) 失敗：" + GetErrorDescription(errCode);
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
            string retcodeMsg = GetRetcodeDescription(result.retcode);
            errorDetails += "\n• 倉位 #" + IntegerToString(positions[i].ticket) + " (" + symbol + ", " + DoubleToString(positions[i].lots, 2) + "手) 失敗：" + retcodeMsg;
            failedCount++;
        }
    }

    Print("[統計] 平倉結果：成功 ", closedCount, " 個（", DoubleToString(actualClosedLots, 2), " 手），失敗 ", failedCount, " 個");

    //--- 生成詳細結果訊息
    g_lastOperationResult = "[統計] 成功 " + IntegerToString(closedCount) + " 個（" + DoubleToString(actualClosedLots, 2) + "手），失敗 " + IntegerToString(failedCount) + " 個";
    if(failedCount > 0)
        g_lastOperationResult += "\n\n[失敗詳情]" + errorDetails;

    return (failedCount == 0) ? actualClosedLots : -1;
}

/**
 * @brief 轉換系統錯誤代碼為可讀說明
 * @param errorCode GetLastError() 返回的錯誤代碼
 * @return 可讀的錯誤說明
 */
string GetErrorDescription(int errorCode)
{
    switch(errorCode)
    {
        // 交易錯誤 (4000-4999)
        case 4000: return "無錯誤 (4000)";
        case 4001: return "錯誤的函數參數 (4001)";
        case 4002: return "函數執行錯誤 (4002)";
        case 4003: return "未定義的交易品種 (4003)";
        case 4004: return "賬戶被禁用 (4004)";
        case 4005: return "舊版客戶端 (4005)";
        case 4006: return "未授權的函數調用 (4006)";
        case 4007: return "請求過於頻繁 (4007)";
        case 4008: return "訂單被鎖定 (4008)";
        case 4009: return "訂單被凍結 (4009)";
        case 4010: return "只能賣出 (4010)";
        case 4011: return "只能買入 (4011)";
        case 4012: return "只能平倉 (4012)";
        case 4013: return "訂單已過期 (4013)";
        case 4014: return "修改被禁止 (4014)";
        case 4015: return "交易環境繁忙 (4015)";
        case 4016: return "超時等待回應 (4016)";
        case 4017: return "無效的交易請求 (4017)";
        case 4018: return "無效的倉位編號 (4018)";
        case 4019: return "無效的成交量 (4019)";
        case 4020: return "無效的價格 (4020)";
        case 4021: return "無效的到期時間 (4021)";
        case 4022: return "無效的訂單狀態 (4022)";
        case 4023: return "訂單不存在 (4023)";
        case 4024: return "無法修改訂單 (4024)";
        case 4025: return "無法刪除訂單 (4025)";
        case 4026: return "無法關閉倉位 (4026)";
        case 4027: return "無法關閉多個倉位 (4027)";
        case 4028: return "倉位已關閉 (4028)";
        case 4029: return "訂單已刪除 (4029)";
        case 4030: return "訂單已執行 (4030)";

        // 交易服務器錯誤 (4050-4099)
        case 4050: return "無效的函數參數值 (4050)";
        case 4051: return "無效的函數參數 (4051)";
        case 4052: return "無效的訂單類型 (4052)";
        case 4053: return "無效的訂單到期時間 (4053)";
        case 4054: return "無效的訂單成交量 (4054)";
        case 4055: return "無效的止損或止盈價格 (4055)";
        case 4056: return "無效的訂單填充類型 (4056)";
        case 4057: return "無效的訂單時間類型 (4057)";
        case 4058: return "無效的訂單參數 (4058)";
        case 4059: return "訂單已被修改 (4059)";
        case 4060: return "訂單已被刪除 (4060)";
        case 4061: return "訂單已被執行 (4061)";
        case 4062: return "訂單已被取消 (4062)";
        case 4063: return "訂單已過期 (4063)";
        case 4064: return "倉位已關閉 (4064)";
        case 4065: return "訂單已填充 (4065)";
        case 4066: return "交易品種不存在 (4066)";
        case 4067: return "交易品種數據不完整 (4067)";
        case 4068: return "交易品種參數無效 (4068)";
        case 4069: return "未授權的交易操作 (4069)";
        case 4070: return "賬戶沒有足夠的保證金 (4070)";

        // 交易執行錯誤 (4750-4760)
        case 4750: return "無效的止損或止盈 (4750)";
        case 4751: return "無效的交易量 (4751)";
        case 4752: return "市場已關閉 (4752)";
        case 4753: return "交易已被禁用 (4753)";
        case 4754: return "資金不足 (4754)";
        case 4755: return "價格已變動 (4755)";
        case 4756: return "止損或止盈距離過近 (4756)";  // 這就是你提到的！
        case 4757: return "無法修改訂單 (4757)";
        case 4758: return "交易流已滿 (4758)";
        case 4759: return "訂單已被修改 (4759)";
        case 4760: return "僅允許多頭倉位 (4760)";
        case 4761: return "僅允許空頭倉位 (4761)";
        case 4762: return "僅允許平倉 (4762)";
        case 4763: return "倉位已存在 (4763)";
        case 4764: return "未知的訂單 (4764)";
        case 4765: return "錯誤的填充類型 (4765)";
        case 4766: return "沒有足夠的資金 (4766)";

        // 運行時錯誤 (5000-5999)
        case 5000: return "文件操作錯誤 (5000)";
        case 5001: return "文件名過長 (5001)";
        case 5002: return "無法打開文件 (5002)";
        case 5003: return "文件寫入錯誤 (5003)";
        case 5004: return "文件讀取錯誤 (5004)";
        case 5005: return "文件不存在 (5005)";
        case 5006: return "無法刪除文件 (5006)";
        case 5007: return "無效的文件句柄 (5007)";
        case 5008: return "文件尾部錯誤 (5008)";
        case 5009: return "文件位置錯誤 (5009)";
        case 5010: return "磁盤已滿 (5010)";

        default:
            if(errorCode >= 4000 && errorCode < 5000)
                return "交易錯誤 (" + IntegerToString(errorCode) + ")";
            else if(errorCode >= 5000 && errorCode < 6000)
                return "運行時錯誤 (" + IntegerToString(errorCode) + ")";
            else
                return "未知錯誤 (" + IntegerToString(errorCode) + ")";
    }
}

/**
 * @brief 轉換交易返回代碼為可讀說明
 * @param retcode 交易返回代碼
 * @return 可讀的錯誤說明
 */
string GetRetcodeDescription(uint retcode)
{
    switch(retcode)
    {
        case TRADE_RETCODE_REQUOTE:           return "價格變動 (10004)";
        case TRADE_RETCODE_REJECT:            return "請求被拒絕 (10006)";
        case TRADE_RETCODE_CANCEL:            return "請求被取消 (10007)";
        case TRADE_RETCODE_PLACED:            return "訂單已下單 (10008)";
        case TRADE_RETCODE_DONE:              return "執行成功 (10009)";
        case TRADE_RETCODE_DONE_PARTIAL:      return "部分執行 (10010)";
        case TRADE_RETCODE_ERROR:             return "一般錯誤 (10011)";
        case TRADE_RETCODE_TIMEOUT:           return "請求超時 (10012)";
        case TRADE_RETCODE_INVALID:           return "無效請求 (10013)";
        case TRADE_RETCODE_INVALID_VOLUME:    return "無效手數 (10014)";
        case TRADE_RETCODE_INVALID_PRICE:     return "無效價格 (10015)";
        case TRADE_RETCODE_INVALID_STOPS:     return "無效止盈止損 (10016)";
        case TRADE_RETCODE_TRADE_DISABLED:    return "交易已禁用 (10017)";
        case TRADE_RETCODE_MARKET_CLOSED:     return "市場已關閉 (10018)";
        case TRADE_RETCODE_NO_MONEY:          return "資金不足 (10019)";
        case TRADE_RETCODE_PRICE_CHANGED:     return "價格已變動 (10020)";
        case TRADE_RETCODE_PRICE_OFF:         return "沒有報價 (10021)";
        case TRADE_RETCODE_INVALID_EXPIRATION: return "無效到期時間 (10022)";
        case TRADE_RETCODE_ORDER_CHANGED:     return "訂單狀態已變更 (10023)";
        case TRADE_RETCODE_TOO_MANY_REQUESTS: return "請求過於頻繁 (10024)";
        case TRADE_RETCODE_NO_CHANGES:        return "沒有變更 (10025)";
        case TRADE_RETCODE_SERVER_DISABLES_AT: return "服務器禁用自動交易 (10026)";
        case TRADE_RETCODE_CLIENT_DISABLES_AT: return "客戶端禁用自動交易 (10027)";
        case TRADE_RETCODE_LOCKED:            return "請求被鎖定 (10028)";
        case TRADE_RETCODE_FROZEN:            return "訂單或倉位已凍結 (10029)";
        case TRADE_RETCODE_INVALID_FILL:      return "無效的成交類型 (10030)";
        case TRADE_RETCODE_CONNECTION:        return "連接錯誤 (10031)";
        case TRADE_RETCODE_ONLY_REAL:         return "僅限真實賬戶 (10032)";
        case TRADE_RETCODE_LIMIT_ORDERS:      return "掛單數量已達上限 (10033)";
        case TRADE_RETCODE_LIMIT_VOLUME:      return "手數達到上限 (10034)";
        case TRADE_RETCODE_INVALID_ORDER:     return "無效訂單 (10035)";
        case TRADE_RETCODE_POSITION_CLOSED:   return "倉位已關閉 (10036)";
        default:                              return "未知錯誤 (" + IntegerToString(retcode) + ")";
    }
}

//+------------------------------------------------------------------+
