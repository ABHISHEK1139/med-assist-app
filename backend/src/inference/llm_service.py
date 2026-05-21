"""
Med Assist App LLM Inference Service
Supports both MediaPipe (mobile) and Transformers (PC with GPU).

For PC: Uses Hugging Face Transformers with Gemma-2B
For Mobile: Uses MediaPipe LLM Inference (to be ported)
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from loguru import logger

try:
    import torch
    CUDA_AVAILABLE = torch.cuda.is_available()
    if CUDA_AVAILABLE:
        logger.info(f"CUDA available: {torch.cuda.get_device_name(0)}")
    else:
        logger.warning("CUDA not available, using CPU")
except ImportError:
    torch = None
    CUDA_AVAILABLE = False
    logger.warning("PyTorch not installed - only MockLLMService available")


@dataclass
class LLMServiceConfig:
    """
    Configuration for the LLM inference service.
    
    Token Budget Guide:
    - Simple chat: 1024 context, 256 response
    - Agentic chat: 2048 context, 512 response (3 rounds)
    - Document analysis: 4096 context, 512 response
    - Full agentic + docs: 4096 context, 1024 response
    
    Gemma-2-2B max context: 8192 tokens
    RTX 3050 4GB can handle up to ~4096 context with 4-bit quant
    """
    model_path: Path
    max_tokens: int = 1024  # Increased for detailed responses
    temperature: float = 0.7
    top_k: int = 40
    use_gpu: bool = True
    model_id: str = "google/gemma-2-2b-it"  # Gemma 2 2B - fits 4GB VRAM
    hf_token: Optional[str] = None
    max_context_length: int = 4096  # Enough for agentic + documents


class LLMService:
    """
    Real LLM Service using Hugging Face Transformers.
    Uses Med Assist App-4B-IT for medical queries with GPU acceleration.
    """
    
    def __init__(self, config: LLMServiceConfig):
        self.config = config
        self._model = None
        self._tokenizer = None
        self._is_initialized = False
        
    def initialize(self) -> bool:
        """Initialize the model with GPU support."""
        try:
            from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
            import os
            
            token_arg = {"token": self.config.hf_token} if self.config.hf_token else {}
            if self.config.hf_token:
                os.environ["HF_TOKEN"] = self.config.hf_token
            
            logger.info(f"Loading model: {self.config.model_id}")
            logger.info("This may take a minute on first run...")
            
            # Load tokenizer
            self._tokenizer = AutoTokenizer.from_pretrained(
                self.config.model_id,
                trust_remote_code=True,
                **token_arg
            )
            
            # Load model with 4-bit quantization for FAST inference
            if CUDA_AVAILABLE and self.config.use_gpu:
                logger.info("Loading model with 4-bit quantization (FAST mode)...")
                
                # Clear GPU memory first
                torch.cuda.empty_cache()
                import gc
                gc.collect()
                
                # 4-bit quantization config - fits in 4GB VRAM and is FAST
                bnb_config = BitsAndBytesConfig(
                    load_in_4bit=True,
                    bnb_4bit_compute_dtype=torch.float16,
                    bnb_4bit_quant_type="nf4",
                    bnb_4bit_use_double_quant=True,
                )
                
                self._model = AutoModelForCausalLM.from_pretrained(
                    self.config.model_id,
                    quantization_config=bnb_config,
                    device_map="cuda:0",  # All on GPU!
                    trust_remote_code=True,
                    **token_arg,
                    low_cpu_mem_usage=True,
                )
                
                # Clear cache after loading
                torch.cuda.empty_cache()
                logger.success("Model loaded with 4-bit quantization! (~10 tokens/sec)")
            else:
                logger.info("Loading model to CPU...")
                self._model = AutoModelForCausalLM.from_pretrained(
                    self.config.model_id,
                    torch_dtype=torch.float32,
                    low_cpu_mem_usage=True,
                    trust_remote_code=True,
                    **token_arg
                )
            
            self._is_initialized = True
            logger.success(f"Model loaded! GPU: {CUDA_AVAILABLE and self.config.use_gpu}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize model: {e}")
            logger.info("Falling back to MockLLMService")
            return False
    
    def generate_response(self, prompt: str) -> str:
        """Generate a response using Gemma."""
        if not self._is_initialized:
            return "[Error: Model not initialized]"
        
        try:
            # Format prompt for Gemma chat template
            messages = [
                {"role": "user", "content": prompt}
            ]
            
            # Apply chat template
            formatted = self._tokenizer.apply_chat_template(
                messages, 
                tokenize=False, 
                add_generation_prompt=True
            )
            
            # Tokenize
            inputs = self._tokenizer(formatted, return_tensors="pt")
            
            # Move inputs to model's device (works with device_map="auto")
            if hasattr(self._model, 'device'):
                inputs = inputs.to(self._model.device)
            elif CUDA_AVAILABLE and self.config.use_gpu:
                # For quantized models, get the device from the first parameter
                first_param = next(self._model.parameters())
                inputs = inputs.to(first_param.device)
            
            # Generate
            with torch.no_grad():
                outputs = self._model.generate(
                    **inputs,
                    max_new_tokens=self.config.max_tokens,
                    temperature=self.config.temperature,
                    top_k=self.config.top_k,
                    do_sample=True,
                    pad_token_id=self._tokenizer.eos_token_id
                )
            
            # Decode response
            response = self._tokenizer.decode(
                outputs[0][inputs.input_ids.shape[1]:], 
                skip_special_tokens=True
            )
            
            # Clean up GPU memory after inference
            del outputs
            del inputs
            if CUDA_AVAILABLE:
                torch.cuda.empty_cache()
            
            return response.strip()
            
        except Exception as e:
            logger.error(f"Generation failed: {e}")
            # Clean up on error too
            if CUDA_AVAILABLE:
                torch.cuda.empty_cache()
            return f"[Error: {str(e)}]"
    
    async def generate_response_async(self, prompt: str) -> AsyncGenerator[str, None]:
        """Async wrapper for streaming (simplified)."""
        response = self.generate_response(prompt)
        yield response
    
    def is_ready(self) -> bool:
        return self._is_initialized and self._model is not None
    
    def close(self) -> None:
        """Release model resources."""
        if self._model is not None:
            del self._model
            del self._tokenizer
            if CUDA_AVAILABLE:
                torch.cuda.empty_cache()
            self._is_initialized = False
            logger.info("Model resources released")
    
    def __enter__(self):
        self.initialize()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class MockLLMService(LLMService):
    """
    Mock LLM service for testing without a real model.
    
    Use this during frontend development or when the model file
    is not yet downloaded.
    """
    
    def initialize(self) -> bool:
        logger.info("Initializing MockLLMService (no real model)")
        self._is_initialized = True
        return True
    
    def generate_response(self, prompt: str) -> str:
        """Return a mock medical response."""
        # Simulate processing time
        import time
        time.sleep(0.5)
        
        return (
            "**Mock Med Assist App Response**\n\n"
            "Based on the information provided, here is my analysis:\n\n"
            "1. **Observation**: The values appear within normal ranges.\n"
            "2. **Recommendation**: Continue monitoring and consult with a "
            "healthcare provider for personalized advice.\n\n"
            "*Note: This is a simulated response for development purposes.*"
        )
    
    def is_ready(self) -> bool:
        return True
