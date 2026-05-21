import os
import asyncio
import logging
from pathlib import Path
from telegram import Update
from telegram.ext import ApplicationBuilder, MessageHandler, filters, ContextTypes, CommandHandler
from loguru import logger as loguru_logger

# Import backend services
from ..inference.llm_service import LLMService, LLMServiceConfig, MockLLMService
from ..inference.image_processor import ImageProcessor
from ..profile.profile_manager import ProfileManager
from ..config import settings

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Global instances
llm_service = None
profile_manager = None
image_processor = ImageProcessor()


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send a welcome message."""
    await update.message.reply_text(
        "👋 Hello! I am Med Assist App, your private medical AI assistant.\n\n"
        "I am running on your Dell G15 server. You can send me messages or medical documents/images.\n"
        "I will also passively archive your medical history."
    )

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming text messages."""
    user_text = update.message.text
    user_id = update.effective_user.id
    
    loguru_logger.info(f"Received message from {user_id}: {user_text}")
    
    # 1. Generate Response
    if llm_service and llm_service.is_ready():
        # Simple prompt for now
        prompt = f"User: {user_text}\nAnswer as a helpful medical assistant."
        loop = asyncio.get_running_loop()
        response = await loop.run_in_executor(None, llm_service.generate_response, prompt)
    else:
        response = "⚠️ AI Model is not ready yet."
        
    await update.message.reply_text(response)
    
    # 2. Passive Profile Extraction (Background)
    if profile_manager and llm_service and llm_service.is_ready():
        loguru_logger.info("Running passive profile extraction...")
        # We don't await this to block the reply, but python-telegram-bot handles async well
        # In a real app we might fire-and-forget, but here we just await it quickly
        await profile_manager.extract_from_message(user_text, llm_service)
        
async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming photos."""
    photo_file = await update.message.photo[-1].get_file()
    
    # Download to temp
    download_path = Path(f"temp_{photo_file.file_unique_id}.jpg")
    await photo_file.download_to_drive(download_path)
    
    loguru_logger.info(f"Downloaded photo to {download_path}")
    
    await update.message.reply_text("📸 Processing image... Please wait a moment.")
    
    # Process image natively
    result = image_processor.process_image(str(download_path))
    context_str = image_processor.build_image_context(result)
    
    if llm_service and llm_service.is_ready():
        prompt = f"User sent an image.\n{context_str}\n\nPlease analyze this medical context and provide helpful insights. Note: State clearly that you cannot replace a real doctor."
        loop = asyncio.get_running_loop()
        response = await loop.run_in_executor(None, llm_service.generate_response, prompt)
    else:
        response = f"⚠️ AI Model is not ready yet.\n\nImage Info: {result.description}"
        
    await update.message.reply_text(response)
    
    # Clean up
    if download_path.exists():
        os.remove(download_path)

def init_services():
    global llm_service, profile_manager
    
    base_dir = Path(__file__).parent.parent.parent
    
    # Profile Manager
    data_dir = base_dir / "data"
    profile_manager = ProfileManager(data_dir)
    loguru_logger.success("Profile Manager initialized")
    
    # LLM Service
    model_path = settings.get_absolute_model_path(base_dir)
    config = LLMServiceConfig(
        model_path=model_path,
        hf_token=settings.hf_token,
        max_tokens=settings.max_tokens,
        temperature=settings.temperature,
        top_k=settings.top_k,
        use_gpu=True # Force GPU as requested
    )
    
    llm_service = LLMService(config)
    loguru_logger.info("Initializing LLM Service (this may take a moment)...")
    
    if llm_service.initialize():
        loguru_logger.success("Real Gemma LLM loaded!")
    else:
        loguru_logger.warning("Real LLM failed, falling back to Mock")
        llm_service = MockLLMService(config)
        llm_service.initialize()

def run_bot():
    """Main entry point."""
    loguru_logger.info("Starting Med Assist App Telegram Bridge...")

    if not settings.telegram_bot_token:
        loguru_logger.error(
            "Telegram bot token is not set. Set MED_ASSIST_APP_TELEGRAM_BOT_TOKEN in .env."
        )
        return
    
    # Initialize services
    init_services()
    
    # Build Bot
    app = ApplicationBuilder().token(settings.telegram_bot_token).build()
    
    # Add Handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), handle_text))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    
    loguru_logger.success("Bot is polling...")
    app.run_polling()

if __name__ == "__main__":
    run_bot()
