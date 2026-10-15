# MT5-PositionMaster

<div align="center">

**通過 Telegram Bot 遠程管理 MetaTrader 5 交易倉位的專業工具**

[![MQL5](https://img.shields.io/badge/MQL5-Expert_Advisor-blue.svg)](https://www.mql5.com/)
[![Telegram Bot API](https://img.shields.io/badge/Telegram-Bot_API-26A5E4?logo=telegram)](https://core.telegram.org/bots/api)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0-orange.svg)](https://github.com/FanYueee/MT5-PositionMaster)

</div>

---

## 專案簡介

MT5-PositionMaster 是一個 MetaTrader 5 Expert Advisor（MT5 EA），集成了完整的 Telegram Bot 功能，讓交易者能夠隨時隨地通過手機遠程管理所有交易倉位（無開倉功能）。無需額外的外部服務器或 Python 腳本，所有功能都在 MT5 內原生運行。

---

## 核心功能

### Telegram Bot 整合

#### 交互式按鈕面板
```
┌─────────────────────────────┐
│   📋 倉位管理面板            │
├─────────────────────────────┤
│ [✂️ 平倉一半] [🚫 平掉全部]  │
│ [🎯 設置TP]   [🛡️ 設置SL]    │
│ [❌ 刪除TP]   [❌ 刪除SL]    │
└─────────────────────────────┘
```

#### 完整指令支持
| 指令 | 功能 | 示例 |
|------|------|------|
| `/menu` | 顯示操作按鈕面板 | `/menu` |
| `/settp <價格>` | 設置所有倉位止盈 | `/settp 2050.50` |
| `/setsl <價格>` | 設置所有倉位止損 | `/setsl 2040.30` |
| `/rtp` | 刪除所有倉位止盈 | `/rtp` |
| `/rsl` | 刪除所有倉位止損 | `/rsl` |
| `/ch` | 平倉約一半倉位 | `/ch` |
| `/ca` | 平掉所有倉位 | `/ca` |
| `/cancel` | 取消當前操作 | `/cancel` |
| `/help` | 顯示幫助資訊 | `/help` |

### 倉位管理功能

#### 止盈/止損管理
- **批量設置 TP/SL** - 一鍵為所有倉位設置相同的止盈止損價格
- **批量刪除 TP/SL** - 快速移除所有倉位的止盈止損設置
- **跨品種操作** - 自動管理所有交易品種的倉位
- **實時反饋** - 每次操作後顯示成功/失敗詳情

#### 平倉功能
- **平倉一半** - 使用貪婪演算法選擇最接近 50% 手數的倉位組合
- **全部平倉** - 一鍵關閉所有開倉倉位
- **單倉位保護** - 僅有 1 個倉位時自動跳過半倉操作
- **詳細統計** - 顯示平倉手數、成功/失敗數量

### 交易通知

EA 會監聽帳戶上的所有成交（手動下單、其他 EA、TP/SL 觸發都包含），主動推送到 Telegram。

#### 新開倉持倉報告
有新倉位開出時，回報該商品同方向的所有倉位：
```
🆕 新開倉：XAUUSD 多單 +1 個
📊 目前 5 個倉位，共 0.10 手
均價：2000.00
🎯 TP 2100.00：+10000 pips ≈ +1000.00 USD
🛡️ SL 1900.00：-10000 pips ≈ -1000.00 USD
```
- **持倉均價** - 按手數加權計算
- **TP/SL 盈虧預估** - 每個倉位打到各自 TP/SL 的價差盈虧總和
- **按商品 + 方向分組** - 多單、空單、不同商品分開計算
- **pips 以 MT5 最小跳動計算** - 例如黃金（2 位小數）0.01 = 1 pip，價差 100 = 10000 pips
- 倉位的 TP/SL 不一致時顯示價格範圍；未設定的倉位會標示並不計入

#### TP / SL 觸發通知
倉位被 TP 或 SL 平掉時通知：
```
🎯 TP 已觸發
XAUUSD 多單：5 個倉位，共 0.10 手
平倉均價：2100.00
價差盈虧：+1000.00 USD
剩餘同向倉位：0 個
```
- **只通知 TP/SL 觸發** - 手動平倉或 `/ca`、`/ch` 不會發送
- **同批合併** - 同時觸發的多個倉位合併成一則訊息
- **價差盈虧** - 不含手續費與隔夜利息

> 通知會在成交後約 2–7 秒送達。斷線期間的通知會暫存，重新連上後補發。EA 未運行期間的成交不會補發。

### 性能優化

- **優化超時** - 5 秒長輪詢 + 5 秒緩衝，避免慢速線路誤判為錯誤
- **並發處理** - 高效的訊息輪詢機制
- **斷線自動重連** - 連續錯誤後自動降頻重試，網路恢復即自動恢復，無需重新掛載 EA

---

## 技術架構

### 系統架構圖

```
┌─────────────────────────────────────────────────────────┐
│                    Telegram Bot                         │
│                  (用戶交互界面)                          │
└────────────────────┬────────────────────────────────────┘
                     │ Long Polling
                     │ (5秒輪詢)
                     ▼
┌─────────────────────────────────────────────────────────┐
│              MT5-PositionMaster EA                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │  訊息處理層                                       │  │
│  │  • ProcessTelegramUpdates()                     │  │
│  │  • ParseAndProcessUpdates()                     │  │
│  │  • ProcessSingleUpdate()                        │  │
│  └───────────────────┬──────────────────────────────┘  │
│                      │                                  │
│  ┌───────────────────┴──────────────────────────────┐  │
│  │  指令路由層                                       │  │
│  │  • ProcessCommand()      (指令處理)              │  │
│  │  • ProcessCallbackQuery() (按鈕點擊處理)        │  │
│  └───────────────────┬──────────────────────────────┘  │
│                      │                                  │
│  ┌───────────────────┴──────────────────────────────┐  │
│  │  狀態管理層                                       │  │
│  │  • UserState (IDLE/WAITING_TP/WAITING_SL)       │  │
│  │  • 自動狀態重置                                   │  │
│  └───────────────────┬──────────────────────────────┘  │
│                      │                                  │
│  ┌───────────────────┴──────────────────────────────┐  │
│  │  業務邏輯層                                       │  │
│  │  • ModifyAllTakeProfit()   (設置止盈)           │  │
│  │  • ModifyAllStopLoss()     (設置止損)           │  │
│  │  • RemoveAllTakeProfit()   (刪除止盈)           │  │
│  │  • RemoveAllStopLoss()     (刪除止損)           │  │
│  │  • CloseHalfPositions()    (平倉一半)           │  │
│  │  • CloseAllPositions()     (平倉全部)           │  │
│  └───────────────────┬──────────────────────────────┘  │
│                      │                                  │
│  ┌───────────────────┴──────────────────────────────┐  │
│  │  交易通知層                                       │  │
│  │  • OnTradeTransaction()    (監聽成交)           │  │
│  │  • BuildPositionReport()   (持倉報告)           │  │
│  │  • FlushTradeNotifications() (合併發送)         │  │
│  └───────────────────┬──────────────────────────────┘  │
│                      │                                  │
│  ┌───────────────────┴──────────────────────────────┐  │
│  │  MT5 交易 API                                     │  │
│  │  • PositionsTotal()                              │  │
│  │  • PositionSelect()                              │  │
│  │  • OrderSend()                                   │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 核心技術特點

#### 長輪詢機制
```mql5
// 5 秒長輪詢 + 5 秒緩衝
getUpdates?offset=<last_id>&timeout=5&allowed_updates=["message","callback_query"]
```

#### Inline Keyboard 實現
```mql5
// JSON 格式的按鈕定義
{
  "inline_keyboard": [
    [
      {"text": "✂️ 平倉一半", "callback_data": "CH"},
      {"text": "🚫 平掉全部", "callback_data": "CA"}
    ],
    [
      {"text": "🎯 設置TP", "callback_data": "SETTP"},
      {"text": "🛡️ 設置SL", "callback_data": "SETSL"}
    ]
  ]
}
```

#### 貪婪演算法（平倉一半）
```
目標：平倉約 50% 手數
算法：貪婪選擇最接近目標的倉位組合

示例：
倉位：[0.1, 0.1, 0.1, 0.1, 0.1] (5個倉位，總計 0.5 手)
目標：0.25 手 (50%)
選擇：前 3 個倉位 (0.3 手) - 最接近目標
```

#### 安全驗證頻道 ID
```mql5
// Chat ID 驗證
if(chatID != InpChatID) {
    SendTelegramMessageToChatID("[錯誤] 未授權訪問！", chatID);
    return;
}
```

---

## 安裝配置

### 前置要求

- 一台常開的電腦並運行 MetaTrader 5 
- Telegram 帳號
- 穩定的網路連接

### 第一步：創建 Telegram Bot

1. **打開 Telegram，搜索 `@BotFather`**

2. **創建新 Bot**

3. **獲取 Bot Token**
   ```
   BotFather 會返回類似這樣的 Token：
   123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890
   ```

### 第二步：獲取 Chat ID

1. **打開剛創建的 Bot，發送任意訊息**

2. **打開以下 URL（替換 <YOUR_BOT_TOKEN>）**
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```

3. **找到 Chat ID**
   ```json
   {
     "result": [{
       "message": {
         "chat": {
           "id": 123456789  ← 這就是你的 Chat ID
         }
       }
     }]
   }
   ```

### 第三步：配置 MT5

1. **允許 WebRequest Telegeam API**
   - 打開 MT5 → 工具 → 選項 → Expert Advisors
   - 勾選 "允許 WebRequest 訪問以下 URL"
   - 添加：`https://api.telegram.org`

2. **複製 EA 程式**
   ```
   將 MT5-PositionMaster.mq5 複製到：
   <MT5目錄>/MQL5/Experts/
   ```

3. **編譯 EA**
   - 在 MT5 中打開 MetaEditor
   - 打開 MT5-PositionMaster.mq5
   - 按 F7 編譯

### 第四步：啟動 EA

1. **拖動 EA 到圖表**
   - 在 MT5 導航器中找到 MT5-PositionMaster
   - 拖動到任意圖表

2. **配置參數**
   ```
   Bot Token:        <貼上你的 Bot Token>
   Chat ID:          <貼上你的 Chat ID>
   輪詢間隔:         2 (秒)
   快速模式:         false (推薦)
   ```

3. **允許自動交易**
   - 確保圖表右上角有圖標，並開啟演算法交易

### 第五步：測試

在 Telegram Bot 中發送：
```
/help
```

如果收到機器人教學訊息，說明設定成功！

---

## 使用指南

### 基本操作流程

#### 方式一：使用按鈕（推薦）

```
┌─────────────────────────────────────────────┐
│ 1. 發送 /menu 顯示操作面板                   │
├─────────────────────────────────────────────┤
│ 2. 點擊按鈕執行操作                          │
│    • 平倉類：立即執行                        │
│    • 設置類：等待輸入價格                    │
│    • 刪除類：立即執行                        │
├─────────────────────────────────────────────┤
│ 3. 查看操作結果                              │
│    • 成功/失敗統計                           │
│    • 詳細錯誤信息                            │
│    • 自動刷新面板                            │
└─────────────────────────────────────────────┘
```

#### 方式二：使用指令

```bash
# 設置止盈
/settp 2050.50

# 設置止損
/setsl 2040.30

# 刪除止盈
/rtp

# 刪除止損
/rsl

# 平倉一半
/ch

# 平掉全部
/ca
```

---

## ⚙️ 配置選項

### EA 輸入參數

| 參數名稱 | 類型 | 默認值 | 說明 |
|---------|------|--------|------|
| `Bot Token` | string | "" | Telegram Bot Token（必填） |
| `Chat ID` | long | 0 | 授權的 Telegram Chat ID（必填） |
| `輪詢間隔` | int | 2 | 訊息輪詢間隔（秒），建議 1-5 |
| `快速模式` | bool | false | 是否啟用快速模式 |

### 快速模式說明

#### 標準模式 (false) - 推薦
- 每次操作後自動刷新面板
- 更好的用戶體驗
- 響應時間：2-6 秒

#### 快速模式 (true) - 性能優先
- 跳過面板自動刷新
- 減少 1 次 API 調用
- 響應時間：1-4 秒
- 需要手動發送 `/menu` 刷新面板

### 網路優化

如果遇到回應慢的問題：

1. **檢查網絡延遲**
   ```bash
   ping api.telegram.org
   ```

2. **調整輪詢間隔**
   - 降低到 1 秒可以更快接收訊息
   - 提高到 5 秒可以減少網絡流量

---

## 安全性

### 內置安全機制

#### 1. Chat ID 驗證
```mql5
// 只允許指定的 Chat ID 使用
if(chatID != InpChatID) {
    Print("[警告] 未授權的 Chat ID 嘗試訪問：", chatID);
    SendTelegramMessageToChatID("[錯誤] 未授權訪問！", chatID);
    return;
}
```

#### 2. 訊息去重
```mql5
// 防止重複處理舊訊息
if(updateID <= g_lastUpdateID)
    return; // 已處理過的訊息
```

#### 3. 斷線自動重連
```mql5
// 連續錯誤 10 次後進入 60 秒冷卻，冷卻結束再重試，無次數上限
if(g_errorCount >= MAX_ERROR_COUNT) {
    if(g_pauseUntil == 0) {
        g_pauseUntil = TimeLocal() + ERROR_COOLDOWN_SECONDS;
        return;
    }
    if(TimeLocal() < g_pauseUntil)
        return;
    g_pauseUntil = 0;   // 冷卻結束，重試一次
}
```
- 重新連上後自動恢復正常輪詢，並發送「✅ 已重新連上 Telegram」通知
- 使用 `TimeLocal()` 計時，休市期間冷卻也會正常倒數

#### 4. 防止重播舊指令
```mql5
// 啟動時連不上 Telegram，建立 update_id 基準前不處理任何指令
if(!g_baselineEstablished) {
    if(GetLatestUpdateID())
        g_baselineEstablished = true;
    return;
}
```

---

## 技術細節

### 訊息處理流程

```
收到更新 → 提取 update_id → 驗證 Chat ID → 判斷類型
    │              │                │              │
    ▼              ▼                ▼              ▼
檢查重複     更新 offset      通過驗證        message 或 callback_query
    │              │                │              │
    ▼              ▼                ▼              ▼
跳過舊訊息   下次輪詢使用   處理訊息/回調   執行相應操作
```

### 狀態機設計

```
STATE_IDLE (空閒)
    │
    ├─ 點擊 [🎯 設置TP] ──→ STATE_WAITING_TP (等待輸入止盈)
    │                           │
    │                           ├─ 輸入數字 ──→ 執行設置 ──→ STATE_IDLE
    │                           ├─ 輸入 cancel ──→ STATE_IDLE
    │                           └─ 點擊其他按鈕 ──→ 自動重置 ──→ STATE_IDLE
    │
    └─ 點擊 [🛡️ 設置SL] ──→ STATE_WAITING_SL (等待輸入止損)
                                │
                                ├─ 輸入數字 ──→ 執行設置 ──→ STATE_IDLE
                                ├─ 輸入 cancel ──→ STATE_IDLE
                                └─ 點擊其他按鈕 ──→ 自動重置 ──→ STATE_IDLE
```

---

## 📄 許可證

本項目採用 MIT 許可證 - 詳見 [LICENSE](LICENSE) 文件
