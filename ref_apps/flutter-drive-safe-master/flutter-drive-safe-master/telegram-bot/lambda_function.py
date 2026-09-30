import json
import os
import telebot
from telebot.handler_backends import StatesGroup, State

TOKEN = os.environ['TELEGRAM_TOKEN']
bot = telebot.TeleBot(TOKEN)

def lambda_handler(event, context):
    try:
        # Parse Telegram update from webhook
        update = telebot.types.Update.de_json(json.loads(event['body']))
        
        # Handle /start command
        if update.message and update.message.text == '/start':
            chat_id = update.message.chat.id
            bot.reply_to(update.message,
                f"Welcome to Safe Drive Monitor!\n\n"
                f"Your Chat ID is:\n"
                f"📱 {chat_id}\n\n"
                f"Please copy this number and paste it in the app.")
        
        return {
            'statusCode': 200,
            'body': json.dumps('OK')
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps('Error processing update')
        }
