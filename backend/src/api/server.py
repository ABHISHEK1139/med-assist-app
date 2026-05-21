"""
Med Assist App FastAPI Server
REST API for the Flutter frontend to communicate with the AI backend.

This layer will be removed when porting to mobile (direct FFI instead).
"""

from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from loguru import logger

from ..config import settings
from ..inference.llm_service import LLMService, LLMServiceConfig, MockLLMService
from ..memory import VectorStore
from ..profile.profile_manager import ProfileManager


# Global service instances
llm_service: Optional[LLMService] = None
vector_store: Optional[VectorStore] = None
profile_manager: Optional[ProfileManager] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan manager.
    
    Initializes AI model and vector store on startup,
    cleans up resources on shutdown.
    """
    global llm_service, vector_store, profile_manager
    
    logger.info("=" * 50)
    logger.info(f"Starting {settings.app_name} v{settings.app_version}")
    logger.info("=" * 50)
    
    # Get base directory
    base_dir = Path(__file__).parent.parent.parent
    
    # Initialize vector store
    memory_path = settings.get_absolute_memory_path(base_dir)
    vector_store = VectorStore(
        persist_directory=memory_path,
        embedding_model=settings.embedding_model,
        retention_days=settings.memory_retention_days
    )
    
    if vector_store.initialize():
        logger.success("Vector store ready")
    else:
        logger.warning("Vector store initialization failed")
        
    # Initialize Profile Manager
    # Store profile in data/ relative to project root
    data_dir = base_dir / "data"
    profile_manager = ProfileManager(data_dir)
    logger.success(f"Profile Manager ready (Data: {data_dir})")
    
    # Initialize LLM service - always try real model first
    model_path = settings.get_absolute_model_path(base_dir)
    
    config = LLMServiceConfig(
        model_path=model_path,
        hf_token=settings.hf_token,
        max_tokens=settings.max_tokens,
        temperature=settings.temperature,
        top_k=settings.top_k,
        use_gpu=settings.use_gpu,
        ai_model=settings.ai_model
    )
    
    # Try to initialize real Gemma model (downloads from HuggingFace)
    llm_service = LLMService(config)
    
    if llm_service.initialize():
        logger.success("Real Gemma LLM model loaded!")
    else:
        logger.warning("Real LLM initialization failed, using mock service")
        llm_service = MockLLMService(config)
        llm_service.initialize()
    
    logger.info(f"Server ready at http://{settings.host}:{settings.port}")
    logger.info("=" * 50)
    
    yield  # Application runs here
    
    # Cleanup
    logger.info("Shutting down...")
    if llm_service:
        llm_service.close()
    logger.info("Goodbye!")


def create_app() -> FastAPI:
    """
    Create and configure the FastAPI application.
    """
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=(
            "Local medical AI assistant API. "
            "This API enables the Flutter frontend to communicate with "
            "the Med Assist App inference engine."
        ),
        docs_url="/docs" if settings.debug else None,
        redoc_url="/redoc" if settings.debug else None,
        lifespan=lifespan
    )
    
    # CORS for Flutter web/desktop development
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Allow all origins for development
        allow_credentials=False,  # Must be False when allow_origins is "*"
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Include routes
    from .routes import router
    app.include_router(router)
    
    return app


def get_llm_service() -> LLMService:
    """Dependency injection for LLM service."""
    return llm_service


def get_vector_store() -> VectorStore:
    """Dependency injection for vector store."""
    return vector_store


def get_profile_manager() -> ProfileManager:
    """Dependency injection for profile manager."""
    return profile_manager
