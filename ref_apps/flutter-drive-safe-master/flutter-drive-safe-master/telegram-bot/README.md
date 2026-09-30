# Safe Drive Monitor - Telegram Bot
This bot provides chat IDs to parents for the Safe Drive Monitor app.
# Deployment Instructions
## Creating the Telegram Bot
1. Open Telegram and search for "@BotFather"
. Start chat with BotFather:
  - Send `/start`
  - Send `/newbot`
  - Enter bot name (e.g., "Safe Drive Monitor")
  - Enter bot username (must end in 'bot', e.g., "safe_drive_monitor_bot")
  - Save the bot token you receive
### 1. Prepare Deployment Package
```
mkdir package
pip install pyTelegramBotAPI -t ./package
cp lambda_function.py ./package
zip -r deployment.zip ./package
```
### 2. AWS Lambda Setup

1. Create new Lambda function
   - Go to AWS Lambda console
   - Click "Create function"
   - Choose "Author from scratch"
   - Name: `safe-drive-telegram-bot`
   - Runtime: Python 3.12
   - Architecture: x86_64
   - Click "Create function"

2. Upload deployment package
   - Go to "Code" tab
   - Click "Upload from"
   - Choose ".zip file"
   - Upload deployment.zip
   - Click "Save"

3. Configure environment variables
   - Go to "Configuration" tab
   - Click "Environment variables"
   - Click "Edit"
   - Add variable:
     - Key: `TELEGRAM_TOKEN`
     - Value: Your Telegram bot token
   - Click "Save"

4. Configure Function URL
   - Go to "Configuration" tab
   - Click "Function URL"
   - Click "Create function URL"
   - Auth type: NONE
   - Invoke mode: BUFFERED
   - Click "Save"

5. Set Telegram Webhook
   - Replace values and visit URL in browser:
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook?url=<YOUR_FUNCTION_URL>
   ```
   - You should see: `{"ok":true,"result":true,"description":"Webhook was set"}`

## Testing

1. Open your bot in Telegram
2. Send `/start`
3. Bot should reply with your chat ID

## Troubleshooting

- Check CloudWatch logs for errors
- Verify environment variables are set
- Ensure webhook is properly configured
- Test function locally using AWS Lambda test events