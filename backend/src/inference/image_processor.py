"""
Image Processing Service for Med Assist App
Handles medical images - extracts text and descriptions.

Since Gemma-2-2B is text-only, we use:
1. OCR for text extraction from lab reports/prescriptions
2. Simple image description for visual analysis

For production, consider adding:
- Moondream2 for actual image understanding
- PaliGemma for medical image analysis
"""

import base64
from pathlib import Path
from typing import Optional, Tuple, List
from dataclasses import dataclass
from loguru import logger


@dataclass
class ImageAnalysisResult:
    """Result from image processing."""
    extracted_text: str
    description: str
    image_type: str  # lab_report, prescription, xray, skin, other
    confidence: float
    warnings: List[str]


class ImageProcessor:
    """
    Process medical images for text-only AI models.
    
    Flow:
    1. Receive image (base64 or file path)
    2. Detect image type (lab report, prescription, x-ray, etc.)
    3. Extract text via OCR if applicable
    4. Generate description for AI context
    """
    
    def __init__(self):
        self._ocr_available = False
        self._vision_available = False
        self._init_ocr()
    
    def _init_ocr(self):
        """Initialize OCR engine if available."""
        try:
            import pytesseract
            from PIL import Image
            self._ocr_available = True
            logger.info("✅ OCR (Tesseract) available for text extraction")
        except ImportError:
            logger.warning("⚠️ OCR not available. Install: pip install pytesseract pillow")
            logger.warning("   Also install Tesseract: https://github.com/tesseract-ocr/tesseract")
    
    def process_image(
        self,
        image_data: str,  # Base64 encoded or file path
        image_type_hint: Optional[str] = None
    ) -> ImageAnalysisResult:
        """
        Process an image and extract information for AI context.
        
        Args:
            image_data: Base64 encoded image or file path
            image_type_hint: Optional hint about image type
            
        Returns:
            ImageAnalysisResult with extracted text and description
        """
        warnings = []
        extracted_text = ""
        description = ""
        
        try:
            # Load image
            image = self._load_image(image_data)
            if image is None:
                return ImageAnalysisResult(
                    extracted_text="",
                    description="Failed to load image",
                    image_type="unknown",
                    confidence=0.0,
                    warnings=["Could not load image"]
                )
            
            # Detect image type
            image_type = image_type_hint or self._detect_image_type(image)
            
            # Extract text if it's a document
            if image_type in ['lab_report', 'prescription', 'medical_record', 'document']:
                if self._ocr_available:
                    extracted_text = self._extract_text_ocr(image)
                    if extracted_text:
                        description = f"Document with extracted text ({len(extracted_text)} chars)"
                    else:
                        warnings.append("OCR found no text in image")
                else:
                    warnings.append("OCR not available - install pytesseract")
            
            # For medical images without text, create description
            if not extracted_text:
                description = self._generate_basic_description(image, image_type)
                warnings.append("Image understanding limited - Gemma is text-only")
            
            return ImageAnalysisResult(
                extracted_text=extracted_text,
                description=description,
                image_type=image_type,
                confidence=0.7 if extracted_text else 0.3,
                warnings=warnings
            )
            
        except Exception as e:
            logger.error(f"Image processing failed: {e}")
            return ImageAnalysisResult(
                extracted_text="",
                description=f"Error processing image: {str(e)}",
                image_type="error",
                confidence=0.0,
                warnings=[str(e)]
            )
    
    def _load_image(self, image_data: str):
        """Load image from base64 or file path."""
        try:
            from PIL import Image
            import io
            
            # Check if it's a file path
            if Path(image_data).exists():
                return Image.open(image_data)
            
            # Try base64 decode
            if ',' in image_data:
                # Data URL format: data:image/png;base64,xxxxx
                image_data = image_data.split(',')[1]
            
            image_bytes = base64.b64decode(image_data)
            return Image.open(io.BytesIO(image_bytes))
            
        except Exception as e:
            logger.error(f"Failed to load image: {e}")
            return None
    
    def _detect_image_type(self, image) -> str:
        """Detect the type of medical image."""
        # Simple heuristics based on image properties
        width, height = image.size
        aspect_ratio = width / height
        
        # Portrait documents are likely reports/prescriptions
        if aspect_ratio < 0.9:
            return "document"
        
        # Very wide images might be panoramic x-rays
        if aspect_ratio > 2:
            return "xray"
        
        # Default to general medical image
        return "medical_image"
    
    def _extract_text_ocr(self, image) -> str:
        """Extract text from image using OCR."""
        try:
            import pytesseract
            
            # Preprocess for better OCR
            image = image.convert('L')  # Grayscale
            
            # Extract text
            text = pytesseract.image_to_string(image)
            
            # Clean up
            text = text.strip()
            if len(text) < 10:
                return ""  # Too little text, probably not a document
            
            return text
            
        except Exception as e:
            logger.error(f"OCR failed: {e}")
            return ""
    
    def _generate_basic_description(self, image, image_type: str) -> str:
        """Generate basic description for non-text images."""
        width, height = image.size
        mode = image.mode
        
        descriptions = {
            "xray": f"X-ray image ({width}x{height}). Note: AI cannot interpret medical imaging directly. Please consult a radiologist.",
            "medical_image": f"Medical image ({width}x{height}). For accurate analysis, please consult a healthcare provider.",
            "skin": f"Skin/dermatology image ({width}x{height}). For skin conditions, please consult a dermatologist.",
            "document": f"Document image ({width}x{height}). Text extraction attempted.",
        }
        
        return descriptions.get(image_type, f"Image ({width}x{height}, {mode} mode)")
    
    def build_image_context(self, result: ImageAnalysisResult) -> str:
        """Build context string for AI prompt."""
        context_parts = []
        
        context_parts.append(f"[IMAGE ATTACHED: {result.image_type}]")
        
        if result.extracted_text:
            # Truncate if too long
            text = result.extracted_text
            if len(text) > 3000:
                text = text[:3000] + "\n... [text truncated for length]"
            context_parts.append(f"\nExtracted Text:\n{text}")
        
        if result.description:
            context_parts.append(f"\nDescription: {result.description}")
        
        if result.warnings:
            context_parts.append(f"\nWarnings: {', '.join(result.warnings)}")
        
        return "\n".join(context_parts)


# Token estimation for images
def estimate_image_tokens(result: ImageAnalysisResult) -> int:
    """Estimate token count for image context."""
    # Rough estimate: 1 token ≈ 4 characters
    text_chars = len(result.extracted_text) + len(result.description)
    return text_chars // 4 + 50  # 50 for metadata


# Quick usage example
if __name__ == "__main__":
    processor = ImageProcessor()
    
    print("Image Processing Service")
    print("=" * 40)
    print(f"OCR Available: {processor._ocr_available}")
    print()
    print("Token Budget for Images:")
    print("- Lab report (1 page OCR): ~500-1500 tokens")
    print("- Prescription (short): ~200-500 tokens")
    print("- X-ray description: ~50-100 tokens")
    print()
    print("With 4096 context limit:")
    print("- System prompt: ~300 tokens")
    print("- Image context: ~1500 tokens")
    print("- Health context: ~500 tokens")
    print("- User question: ~100 tokens")
    print("- Agentic tools: ~500 tokens")
    print("─" * 40)
    print("Total: ~2900 tokens ✅ (fits in 4096)")
