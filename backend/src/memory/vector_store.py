"""
Med Assist App Vector Store
ChromaDB-based local vector database for RAG memory.

This mirrors the ObjectBox + vector search pattern you'll use on mobile.
The logic here transfers directly to Kotlin with minimal changes.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Optional, Dict, Any
from loguru import logger

try:
    import chromadb
    from chromadb.config import Settings as ChromaSettings
    CHROMADB_AVAILABLE = True
except ImportError:
    CHROMADB_AVAILABLE = False
    logger.warning("ChromaDB not installed. Memory features disabled.")


@dataclass
class DocumentMetadata:
    """
    Metadata for a stored health document.
    
    This structure maps to ObjectBox entities on mobile.
    """
    doc_id: str
    source: str  # Original filename or "user_input"
    doc_type: str  # "lab_report", "prescription", "note", etc.
    timestamp: datetime
    summary: str = ""
    tags: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for ChromaDB storage."""
        return {
            "doc_id": self.doc_id,
            "source": self.source,
            "doc_type": self.doc_type,
            "timestamp": self.timestamp.isoformat(),
            "summary": self.summary,
            "tags": ",".join(self.tags)
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "DocumentMetadata":
        """Create from ChromaDB metadata dictionary."""
        return cls(
            doc_id=data.get("doc_id", ""),
            source=data.get("source", "unknown"),
            doc_type=data.get("doc_type", "unknown"),
            timestamp=datetime.fromisoformat(data.get("timestamp", datetime.now().isoformat())),
            summary=data.get("summary", ""),
            tags=data.get("tags", "").split(",") if data.get("tags") else []
        )


@dataclass
class SearchResult:
    """A single search result from the vector store."""
    content: str
    metadata: DocumentMetadata
    relevance_score: float
    
    def to_context_document(self):
        """Convert to ContextDocument for prompt building."""
        from .document_processor import DocumentProcessor
        from ..inference.prompt_templates import ContextDocument
        
        return ContextDocument(
            content=self.content,
            source=self.metadata.source,
            timestamp=self.metadata.timestamp.strftime("%Y-%m-%d"),
            doc_type=self.metadata.doc_type
        )


class VectorStore:
    """
    ChromaDB wrapper for local RAG memory.
    
    Key features:
    - Persistent local storage (survives app restarts)
    - Semantic search for relevant health documents
    - Automatic cleanup of old documents
    - Explainability: track which documents were used
    
    Mobile porting note:
    Replace this with ObjectBox + VectorSearch on Android.
    The method signatures stay the same.
    """
    
    COLLECTION_NAME = "health_documents"
    
    def __init__(
        self, 
        persist_directory: Path,
        embedding_model: str = "all-MiniLM-L6-v2",
        retention_days: int = 30
    ):
        self.persist_directory = persist_directory
        self.embedding_model = embedding_model
        self.retention_days = retention_days
        self._client: Optional[chromadb.Client] = None
        self._collection = None
        self._embedding_function = None
        
    def initialize(self) -> bool:
        """
        Initialize the vector store.
        
        Returns:
            True if initialization successful.
        """
        if not CHROMADB_AVAILABLE:
            logger.error("ChromaDB not installed")
            return False
            
        try:
            # Ensure directory exists
            self.persist_directory.mkdir(parents=True, exist_ok=True)
            
            # Initialize ChromaDB with persistence
            self._client = chromadb.PersistentClient(
                path=str(self.persist_directory),
                settings=ChromaSettings(
                    anonymized_telemetry=False,  # Privacy first!
                    allow_reset=True
                )
            )
            
            # Set up embedding function
            try:
                from chromadb.utils import embedding_functions
                self._embedding_function = embedding_functions.SentenceTransformerEmbeddingFunction(
                    model_name=self.embedding_model
                )
            except Exception as e:
                logger.warning(f"Custom embeddings failed, using default: {e}")
                self._embedding_function = None
            
            # Get or create collection
            self._collection = self._client.get_or_create_collection(
                name=self.COLLECTION_NAME,
                embedding_function=self._embedding_function,
                metadata={"description": "Med Assist App health document memory"}
            )
            
            doc_count = self._collection.count()
            logger.success(f"Vector store initialized. Documents: {doc_count}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize vector store: {e}")
            return False
    
    def add_document(
        self,
        content: str,
        metadata: DocumentMetadata,
        chunk_size: int = 500
    ) -> List[str]:
        """
        Add a document to the vector store.
        
        Long documents are automatically chunked for better retrieval.
        
        Args:
            content: The document text
            metadata: Document metadata
            chunk_size: Maximum characters per chunk
            
        Returns:
            List of chunk IDs created
        """
        if self._collection is None:
            logger.error("Vector store not initialized")
            return []
        
        # Chunk the document
        chunks = self._chunk_text(content, chunk_size)
        chunk_ids = []
        
        for i, chunk in enumerate(chunks):
            chunk_id = f"{metadata.doc_id}_chunk_{i}"
            chunk_metadata = metadata.to_dict()
            chunk_metadata["chunk_index"] = i
            chunk_metadata["total_chunks"] = len(chunks)
            
            try:
                self._collection.add(
                    documents=[chunk],
                    metadatas=[chunk_metadata],
                    ids=[chunk_id]
                )
                chunk_ids.append(chunk_id)
            except Exception as e:
                logger.error(f"Failed to add chunk {chunk_id}: {e}")
        
        logger.info(f"Added document '{metadata.source}' ({len(chunks)} chunks)")
        return chunk_ids
    
    def search(
        self,
        query: str,
        n_results: int = 5,
        doc_type_filter: Optional[str] = None,
        max_age_days: Optional[int] = None
    ) -> List[SearchResult]:
        """
        Search for relevant documents.
        
        Args:
            query: Search query (natural language)
            n_results: Maximum results to return
            doc_type_filter: Filter by document type
            max_age_days: Only include documents from the last N days
            
        Returns:
            List of SearchResult objects with relevance scores
        """
        if self._collection is None:
            logger.error("Vector store not initialized")
            return []
        
        try:
            # Build where filter
            where_filter = None
            if doc_type_filter:
                where_filter = {"doc_type": doc_type_filter}
            
            # Query the collection
            results = self._collection.query(
                query_texts=[query],
                n_results=n_results,
                where=where_filter
            )
            
            # Process results
            search_results = []
            if results and results["documents"] and results["documents"][0]:
                for i, doc in enumerate(results["documents"][0]):
                    metadata = DocumentMetadata.from_dict(
                        results["metadatas"][0][i] if results["metadatas"] else {}
                    )
                    
                    # Filter by age if specified
                    if max_age_days:
                        age = datetime.now() - metadata.timestamp
                        if age.days > max_age_days:
                            continue
                    
                    # Distance to relevance score (lower distance = higher relevance)
                    distance = results["distances"][0][i] if results["distances"] else 0
                    relevance = max(0, 1 - distance)
                    
                    search_results.append(SearchResult(
                        content=doc,
                        metadata=metadata,
                        relevance_score=relevance
                    ))
            
            logger.debug(f"Search returned {len(search_results)} results for: {query[:50]}...")
            return search_results
            
        except Exception as e:
            logger.error(f"Search failed: {e}")
            return []
    
    def get_document_sources(self, doc_ids: List[str]) -> List[DocumentMetadata]:
        """
        Get metadata for specific documents (for explainability).
        
        This powers the "Why?" button showing which documents
        influenced the AI's response.
        """
        if self._collection is None:
            return []
            
        try:
            results = self._collection.get(ids=doc_ids)
            return [
                DocumentMetadata.from_dict(meta)
                for meta in (results.get("metadatas") or [])
            ]
        except Exception as e:
            logger.error(f"Failed to get document sources: {e}")
            return []
    
    def cleanup_old_documents(self, retention_days: Optional[int] = None) -> int:
        """
        Remove documents older than retention period.
        
        Args:
            retention_days: Override default retention period
            
        Returns:
            Number of documents removed
        """
        if self._collection is None:
            return 0
            
        days = retention_days or self.retention_days
        cutoff = datetime.now() - timedelta(days=days)
        
        try:
            # Get all documents
            all_docs = self._collection.get()
            if not all_docs or not all_docs["ids"]:
                return 0
            
            # Find old documents
            ids_to_delete = []
            for i, meta in enumerate(all_docs.get("metadatas") or []):
                try:
                    timestamp = datetime.fromisoformat(meta.get("timestamp", ""))
                    if timestamp < cutoff:
                        ids_to_delete.append(all_docs["ids"][i])
                except (ValueError, KeyError):
                    continue
            
            # Delete old documents
            if ids_to_delete:
                self._collection.delete(ids=ids_to_delete)
                logger.info(f"Cleaned up {len(ids_to_delete)} old documents")
            
            return len(ids_to_delete)
            
        except Exception as e:
            logger.error(f"Cleanup failed: {e}")
            return 0
    
    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about the vector store."""
        if self._collection is None:
            return {"status": "not_initialized"}
            
        return {
            "status": "ready",
            "total_documents": self._collection.count(),
            "persist_directory": str(self.persist_directory),
            "embedding_model": self.embedding_model,
            "retention_days": self.retention_days
        }
    
    def list_all_documents(self) -> List[DocumentMetadata]:
        """
        List all unique documents in the vector store.
        
        Returns metadata for each document (not individual chunks).
        """
        if self._collection is None:
            return []
            
        try:
            all_docs = self._collection.get()
            if not all_docs or not all_docs["metadatas"]:
                return []
            
            # Deduplicate by doc_id (since documents are chunked)
            seen_doc_ids = set()
            unique_docs = []
            
            for meta in all_docs.get("metadatas") or []:
                doc_id = meta.get("doc_id", "")
                if doc_id and doc_id not in seen_doc_ids:
                    seen_doc_ids.add(doc_id)
                    unique_docs.append(DocumentMetadata.from_dict(meta))
            
            # Sort by timestamp (newest first)
            unique_docs.sort(key=lambda x: x.timestamp, reverse=True)
            return unique_docs
            
        except Exception as e:
            logger.error(f"Failed to list documents: {e}")
            return []
    
    def _chunk_text(self, text: str, chunk_size: int) -> List[str]:
        """Split text into chunks, trying to break at sentence boundaries."""
        if len(text) <= chunk_size:
            return [text]
        
        chunks = []
        current_chunk = ""
        
        # Split by sentences (simple approach)
        sentences = text.replace("\n", " ").split(". ")
        
        for sentence in sentences:
            if len(current_chunk) + len(sentence) + 2 <= chunk_size:
                current_chunk += sentence + ". "
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = sentence + ". "
        
        if current_chunk:
            chunks.append(current_chunk.strip())
        
        return chunks if chunks else [text[:chunk_size]]
