"""
Med Assist App Backend Entry Point
Local Medical AI Server

Usage:
    python main.py                    # Start server (default: http://127.0.0.1:8000)
    python main.py --port 8080        # Custom port
    python main.py --debug            # Enable debug mode with API docs

For development without a model file:
    The server will automatically use MockLLMService if the model
    file is not found, allowing frontend development to proceed.
"""

import argparse
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent))

import uvicorn
from loguru import logger

from src.config import settings
from src.api.server import create_app


def configure_logging(debug: bool = False):
    """Configure loguru for the application."""
    logger.remove()  # Remove default handler
    
    log_format = (
        "<green>{time:HH:mm:ss}</green> | "
        "<level>{level: <8}</level> | "
        "<cyan>{name}</cyan>:<cyan>{function}</cyan> - "
        "<level>{message}</level>"
    )
    
    if debug:
        logger.add(
            sys.stderr,
            format=log_format,
            level="DEBUG",
            colorize=True
        )
    else:
        logger.add(
            sys.stderr,
            format=log_format,
            level="INFO",
            colorize=True
        )
    
    # Also log to file
    log_dir = Path(__file__).parent / "logs"
    log_dir.mkdir(exist_ok=True)
    
    logger.add(
        log_dir / "Med Assist App.log",
        rotation="10 MB",
        retention="7 days",
        level="DEBUG"
    )


def main():
    """Main entry point for the Med Assist App backend server."""
    parser = argparse.ArgumentParser(
        description="Med Assist App - Local Medical AI Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python main.py                    Start server on default port 8000
  python main.py --port 8080        Use custom port
  python main.py --debug            Enable debug mode with API docs
  python main.py --host 0.0.0.0     Allow external connections

Model Setup:
  1. Download Med Assist App .task file from Hugging Face:
     https://huggingface.co/collections/google/mediapipe-llm
  
  2. Place the file in: backend/models/med-assist-app-2b.task
  
  3. Or set environment variable:
     MED_ASSIST_APP_MODEL_PATH=/path/to/your/model.task
        """
    )
    
    parser.add_argument(
        "--host",
        type=str,
        default=settings.host,
        help=f"Host to bind to (default: {settings.host})"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=settings.port,
        help=f"Port to bind to (default: {settings.port})"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug mode (enables /docs endpoint)"
    )
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable auto-reload for development"
    )
    
    args = parser.parse_args()
    
    # Update settings
    settings.debug = args.debug
    settings.host = args.host
    settings.port = args.port
    
    # Configure logging
    configure_logging(debug=args.debug)
    
    # Print startup banner (ASCII only for Windows compatibility)
    print("""
    +==============================================================+
    |                                                              |
    |   M M M EEEEE DDDD   GGG  EEEEE M M M   A                   |
    |   M M M E     D   D G     E     M M M  A A                  |
    |   M   M EEE   D   D G GGG EEE   M   M AAAAA                 |
    |   M   M E     D   D G   G E     M   M A   A                 |
    |   M   M EEEEE DDDD   GGG  EEEEE M   M A   A                 |
    |                                                              |
    |              Local Medical AI Assistant v0.1.0               |
    |                                                              |
    +==============================================================+
    """)
    
    logger.info(f"Starting server at http://{args.host}:{args.port}")
    
    if args.debug:
        logger.info("Debug mode enabled - API docs at /docs")
    
    # Create and run the application
    app = create_app()
    
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="debug" if args.debug else "info"
    )


if __name__ == "__main__":
    main()
