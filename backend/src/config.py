"""
Med Assist App Configuration Management
Centralized settings for the local medical AI backend.
"""

from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Application settings loaded from environment or .env file."""
    
    # Application
    app_name: str = "Med Assist App"
    app_version: str = "0.1.0"
    debug: bool = False
    
    # Server
    host: str = "127.0.0.1"
    port: int = 8000
    
    # Model Configuration
    model_path: Path = Field(
        default=Path("models/med-assist-app-2b.task"),
        description="Path to the MediaPipe .task model file"
    )
    hf_token: Optional[str] = Field(
        default=None,
        description="Hugging Face token (only needed for gated models)"
    )
    ai_model: str = Field(
        default="local/gemma-2-2b-it",
        description="The AI model to use. Format: provider/model (e.g., openai/gpt-4o, gemini/gemini-1.5-pro) or local/model."
    )
    max_tokens: int = 1024
    temperature: float = 0.7
    top_k: int = 40
    
    # Memory/RAG Configuration
    memory_path: Path = Field(
        default=Path("memory"),
        description="Path to ChromaDB vector store"
    )
    embedding_model: str = "all-MiniLM-L6-v2"
    max_context_documents: int = 5
    memory_retention_days: int = 30
    
    # GPU Settings
    use_gpu: bool = True
    gpu_device_id: int = 0

    # Integrations
    telegram_bot_token: Optional[str] = Field(
        default=None,
        description="Telegram bot token for the optional bot bridge"
    )
    
    class Config:
        env_prefix = "MED_ASSIST_APP_"
        env_file = ".env"
        env_file_encoding = "utf-8"
    
    def get_absolute_model_path(self, base_dir: Path) -> Path:
        """Get absolute path to model file."""
        if self.model_path.is_absolute():
            return self.model_path
        return base_dir / self.model_path
    
    def get_absolute_memory_path(self, base_dir: Path) -> Path:
        """Get absolute path to memory directory."""
        if self.memory_path.is_absolute():
            return self.memory_path
        return base_dir / self.memory_path


# Global settings instance
settings = Settings()
