"""
Med Assist App Document Processor
Handles extraction and preprocessing of medical documents.

Supports: PDF (lab reports), images (prescriptions, X-rays), plain text.
"""

import hashlib
import mimetypes
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple, BinaryIO
from loguru import logger

try:
    from pypdf import PdfReader
    PDF_AVAILABLE = True
except ImportError:
    PDF_AVAILABLE = False

try:
    from PIL import Image
    IMAGE_AVAILABLE = True
except ImportError:
    IMAGE_AVAILABLE = False


@dataclass
class ProcessedDocument:
    """Result of document processing."""
    doc_id: str
    content: str
    doc_type: str
    source_filename: str
    page_count: int = 1
    processing_notes: str = ""


class DocumentProcessor:
    """
    Process various medical document formats for storage and analysis.
    
    This class handles:
    - PDF extraction (lab reports, medical records)
    - Image preprocessing (prescriptions, X-rays)
    - Text normalization
    - Document type classification
    
    Mobile porting note:
    Replace with Android's PdfRenderer and ML Kit for similar functionality.
    """
    
    # Document type patterns for auto-classification
    DOC_TYPE_PATTERNS = {
        "lab_report": ["glucose", "hemoglobin", "cholesterol", "wbc", "rbc", "lab", "test results"],
        "prescription": ["rx", "prescription", "medication", "dosage", "refill", "pharmacy"],
        "radiology": ["x-ray", "xray", "ct scan", "mri", "imaging", "radiology"],
        "notes": ["doctor's note", "medical note", "consultation", "follow-up"],
    }
    
    def __init__(self, enable_ocr: bool = False):
        """
        Initialize the document processor.
        
        Args:
            enable_ocr: Enable OCR for images (requires tesseract)
        """
        self.enable_ocr = enable_ocr
        
    def process_file(
        self, 
        file_path: Path,
        doc_type_hint: Optional[str] = None
    ) -> Optional[ProcessedDocument]:
        """
        Process a file and extract its content.
        
        Args:
            file_path: Path to the file
            doc_type_hint: Optional hint for document type
            
        Returns:
            ProcessedDocument or None if processing failed
        """
        if not file_path.exists():
            logger.error(f"File not found: {file_path}")
            return None
        
        # Detect file type
        mime_type, _ = mimetypes.guess_type(str(file_path))
        
        # Generate document ID
        doc_id = self._generate_doc_id(file_path)
        
        # Process based on type
        content = ""
        page_count = 1
        processing_notes = ""
        
        if mime_type == "application/pdf":
            content, page_count, processing_notes = self._process_pdf(file_path)
        elif mime_type and mime_type.startswith("image/"):
            content, processing_notes = self._process_image(file_path)
        elif mime_type and mime_type.startswith("text/"):
            content = file_path.read_text(encoding="utf-8", errors="ignore")
        else:
            # Try as text
            try:
                content = file_path.read_text(encoding="utf-8", errors="ignore")
            except Exception as e:
                logger.error(f"Cannot process file type {mime_type}: {e}")
                return None
        
        if not content.strip():
            logger.warning(f"No content extracted from: {file_path}")
            return None
        
        # Determine document type
        doc_type = doc_type_hint or self._classify_document(content)
        
        return ProcessedDocument(
            doc_id=doc_id,
            content=self._normalize_text(content),
            doc_type=doc_type,
            source_filename=file_path.name,
            page_count=page_count,
            processing_notes=processing_notes
        )
    
    def process_bytes(
        self,
        file_data: BinaryIO,
        filename: str,
        doc_type_hint: Optional[str] = None
    ) -> Optional[ProcessedDocument]:
        """
        Process file data from bytes (for API uploads).
        
        Args:
            file_data: File-like object with read() method
            filename: Original filename
            doc_type_hint: Optional document type hint
        """
        # Create temporary file for processing
        import tempfile
        
        suffix = Path(filename).suffix
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(file_data.read())
            tmp_path = Path(tmp.name)
        
        try:
            result = self.process_file(tmp_path, doc_type_hint)
            if result:
                result.source_filename = filename
            return result
        finally:
            tmp_path.unlink(missing_ok=True)
    
    def _process_pdf(self, file_path: Path) -> Tuple[str, int, str]:
        """Extract text from PDF file."""
        if not PDF_AVAILABLE:
            return "", 0, "PDF processing not available (install pypdf)"
        
        try:
            reader = PdfReader(file_path)
            pages = []
            
            for page in reader.pages:
                text = page.extract_text() or ""
                pages.append(text)
            
            content = "\n\n".join(pages)
            return content, len(reader.pages), ""
            
        except Exception as e:
            logger.error(f"PDF processing failed: {e}")
            return "", 0, f"PDF error: {str(e)}"
    
    def _process_image(self, file_path: Path) -> Tuple[str, str]:
        """
        Process an image file.
        
        For now, returns a placeholder. OCR can be added later.
        Mobile note: Use ML Kit's Text Recognition on Android.
        """
        if not IMAGE_AVAILABLE:
            return "", "Image processing not available (install Pillow)"
        
        try:
            with Image.open(file_path) as img:
                width, height = img.size
                format_info = img.format or "unknown"
                
            # Placeholder content - OCR would go here
            content = (
                f"[Image: {file_path.name}]\n"
                f"Format: {format_info}, Size: {width}x{height}\n"
                f"Note: Image content requires visual analysis by the AI model."
            )
            
            if self.enable_ocr:
                # TODO: Integrate tesseract OCR if needed
                pass
            
            return content, ""
            
        except Exception as e:
            logger.error(f"Image processing failed: {e}")
            return "", f"Image error: {str(e)}"
    
    def _classify_document(self, content: str) -> str:
        """
        Auto-classify document type based on content.
        
        Uses simple keyword matching - could be enhanced with ML.
        """
        content_lower = content.lower()
        
        scores = {}
        for doc_type, patterns in self.DOC_TYPE_PATTERNS.items():
            score = sum(1 for pattern in patterns if pattern in content_lower)
            if score > 0:
                scores[doc_type] = score
        
        if scores:
            return max(scores, key=scores.get)
        
        return "general"
    
    def _normalize_text(self, text: str) -> str:
        """Normalize extracted text for better embedding."""
        # Remove excessive whitespace
        lines = text.split("\n")
        cleaned_lines = []
        
        for line in lines:
            line = " ".join(line.split())  # Normalize whitespace
            if line:
                cleaned_lines.append(line)
        
        return "\n".join(cleaned_lines)
    
    def _generate_doc_id(self, file_path: Path) -> str:
        """Generate a unique document ID."""
        # Use file content hash + timestamp for uniqueness
        content_hash = hashlib.md5(file_path.read_bytes()).hexdigest()[:8]
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        return f"doc_{timestamp}_{content_hash}"
