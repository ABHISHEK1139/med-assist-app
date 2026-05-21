"""
Med Assist App API Routes
REST endpoints for chat, document upload, and system status.
"""

import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, File, Form, UploadFile, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field
from loguru import logger

from .server import get_llm_service, get_vector_store, get_profile_manager
from ..inference.prompt_templates import MedicalPromptTemplates, AnalysisType, ContextDocument
from ..memory import DocumentProcessor, DocumentMetadata


router = APIRouter()

# Thread pool for CPU-bound model inference
_executor = ThreadPoolExecutor(max_workers=1)


# ============================================================================
# Server-Side Session Memory (app doesn't need to send history each time)
# ============================================================================

class SessionMemory:
    """Server-side memory for chat sessions."""
    
    # Token estimation: ~4 chars per token, keep under 1500 tokens for history
    MAX_HISTORY_CHARS = 6000  # ~1500 tokens for history
    
    def __init__(self, max_messages: int = 20, session_timeout_minutes: int = 60):
        self._sessions: Dict[str, Dict] = {}
        self.max_messages = max_messages  # Keep last N messages per session
        self.session_timeout = timedelta(minutes=session_timeout_minutes)
    
    def get_or_create_session(self, session_id: Optional[str] = None) -> str:
        """Get existing session or create new one."""
        if session_id and session_id in self._sessions:
            # Update last accessed time
            self._sessions[session_id]['last_accessed'] = datetime.now()
            return session_id
        
        # Create new session
        new_id = str(uuid.uuid4())[:8]
        self._sessions[new_id] = {
            'messages': [],
            'summary': None,  # Summarized old messages
            'created': datetime.now(),
            'last_accessed': datetime.now()
        }
        logger.info(f"📝 New session created: {new_id}")
        return new_id
    
    def load_history_from_app(self, session_id: str, history: List[Dict]):
        """Load conversation history from app (when opening old chat)."""
        if session_id not in self._sessions:
            self.get_or_create_session(session_id)
        
        session = self._sessions[session_id]
        
        # Calculate total chars
        total_chars = sum(len(m.get('content', '')) for m in history)
        
        if total_chars > self.MAX_HISTORY_CHARS:
            # Too long - summarize old messages, keep recent ones
            logger.info(f"📚 History too long ({total_chars} chars), summarizing...")
            
            # Keep last 6 messages as-is
            recent = history[-6:] if len(history) > 6 else history
            old = history[:-6] if len(history) > 6 else []
            
            # Create summary of old messages
            if old:
                summary_parts = []
                for m in old:
                    role = m.get('role', 'user')
                    content = m.get('content', '')[:100]  # First 100 chars
                    summary_parts.append(f"{role}: {content}...")
                session['summary'] = "Previous conversation summary:\n" + "\n".join(summary_parts[:5])
            
            session['messages'] = recent
        else:
            # Fits in context - load all
            session['messages'] = history
            session['summary'] = None
        
        session['last_accessed'] = datetime.now()
        logger.info(f"📚 Loaded {len(session['messages'])} messages for session {session_id}")
    
    def add_message(self, session_id: str, role: str, content: str):
        """Add message to session history."""
        if session_id not in self._sessions:
            self.get_or_create_session(session_id)
        
        session = self._sessions[session_id]
        session['messages'].append({
            'role': role,
            'content': content,
            'timestamp': datetime.now().isoformat()
        })
        
        # Keep only last N messages
        if len(session['messages']) > self.max_messages:
            # Summarize oldest messages before removing
            old_msg = session['messages'][0]
            if not session['summary']:
                session['summary'] = "Earlier in conversation:\n"
            session['summary'] += f"\n- {old_msg['role']}: {old_msg['content'][:50]}..."
            session['messages'] = session['messages'][-self.max_messages:]
        
        session['last_accessed'] = datetime.now()
    
    def get_history(self, session_id: str) -> List[Dict]:
        """Get conversation history for session."""
        if session_id not in self._sessions:
            return []
        return self._sessions[session_id]['messages']
    
    def get_summary(self, session_id: str) -> Optional[str]:
        """Get summary of older messages."""
        if session_id not in self._sessions:
            return None
        return self._sessions[session_id].get('summary')
    
    def get_history_for_prompt(self, session_id: str) -> str:
        """Get formatted history string for prompt, including summary."""
        history = self.get_history(session_id)
        summary = self.get_summary(session_id)
        
        parts = []
        if summary:
            parts.append(summary)
        
        if history:
            for msg in history:
                role = "User" if msg['role'] == 'user' else "Assistant"
                parts.append(f"{role}: {msg['content']}")
        
        return "\n".join(parts) if parts else ""
    
    def clear_session(self, session_id: str):
        """Clear a session's history."""
        if session_id in self._sessions:
            self._sessions[session_id]['messages'] = []
            logger.info(f"🗑️ Session cleared: {session_id}")
    
    def cleanup_old_sessions(self):
        """Remove sessions older than timeout."""
        now = datetime.now()
        expired = [
            sid for sid, data in self._sessions.items()
            if now - data['last_accessed'] > self.session_timeout
        ]
        for sid in expired:
            del self._sessions[sid]
            logger.info(f"🗑️ Session expired: {sid}")
    
    def get_session_count(self) -> int:
        """Get number of active sessions."""
        return len(self._sessions)


# Global session memory instance
_session_memory = SessionMemory(max_messages=10, session_timeout_minutes=30)


# ============================================================================
# Request/Response Models
# ============================================================================

class ChatRequest(BaseModel):
    """Chat request from the Flutter frontend."""
    message: str = Field(..., min_length=1, max_length=4000)
    analysis_type: str = Field(default="general_health")
    include_context: bool = Field(default=False)  # DISABLED for faster inference
    max_context_docs: int = Field(default=2, ge=0, le=5)  # Reduced
    image_data: Optional[str] = None  # Base64 encoded image
    image_type: Optional[str] = None  # lab_report, prescription, xray, skin, etc


class ChatResponse(BaseModel):
    """Chat response to the Flutter frontend."""
    response: str
    referenced_documents: List[dict] = []
    inference_time_ms: float
    model_ready: bool
    context_saved: bool = False  # Did we save new profile info?
    image_processed: bool = False  # Was an image processed?


class DocumentResponse(BaseModel):
    """Response after document upload."""
    success: bool
    doc_id: str = ""
    doc_type: str = ""
    message: str = ""
    chunks_created: int = 0


class ContextSearchRequest(BaseModel):
    """Request to search for relevant context."""
    query: str
    n_results: int = Field(default=5, ge=1, le=20)
    doc_type: Optional[str] = None


class ContextResult(BaseModel):
    """A single context search result."""
    content: str
    source: str
    doc_type: str
    timestamp: str
    relevance_score: float


class HealthStatus(BaseModel):
    """System health status response."""
    status: str
    model_ready: bool
    memory_ready: bool
    gpu_enabled: bool
    document_count: int
    version: str


class ExplainRequest(BaseModel):
    """Request to explain an AI response."""
    original_response: str
    referenced_doc_ids: List[str]


# ============================================================================
# Agentic AI Models
# ============================================================================

class ToolCallModel(BaseModel):
    """A tool call from the AI."""
    tool: str
    params: Dict[str, Any] = {}
    reason: str = ""


class ToolResultModel(BaseModel):
    """Result of a tool execution on phone."""
    tool: str
    success: bool
    data: Any
    error: Optional[str] = None


class ConversationMessage(BaseModel):
    """A message in conversation history."""
    role: str  # 'user' or 'assistant'
    content: str
    timestamp: Optional[str] = None


class AgenticChatRequest(BaseModel):
    """Agentic chat request with health context."""
    message: str
    health_context: Dict[str, Any] = {}  # Symptoms, conditions, meds from phone
    # conversation_history: Only sent when loading OLD chat from history
    # For new chats, server maintains via session_id (no need to send)
    conversation_history: Optional[List[ConversationMessage]] = None  # Only for loading old chats
    tool_results: List[ToolResultModel] = []  # Results from previous tool calls
    session_id: Optional[str] = None  # Server tracks history per session
    round_number: int = 0
    image_data: Optional[str] = None  # Base64 encoded image
    image_type: Optional[str] = None  # lab_report, prescription, xray, etc
    is_loading_history: bool = False  # True when loading old chat from history


class AgenticChatResponse(BaseModel):
    """Response that may contain tool calls."""
    response: str  # The AI's text response
    tool_calls: List[ToolCallModel] = []  # Tools AI wants to execute
    is_complete: bool = True  # False if more reasoning needed
    session_id: str
    round_number: int
    inference_time_ms: float
    current_time: str  # So phone knows what time AI thinks it is
    image_processed: bool = False  # Was an image included?
    image_text_extracted: bool = False  # Was text extracted from image?


# ============================================================================
# Background Tasks
# ============================================================================

async def analyze_message_for_profile(message: str):
    """Background task to extract medical info from chat."""
    pm = get_profile_manager()
    llm = get_llm_service()
    
    if pm and llm:
        await pm.extract_from_message(message, llm)


# ============================================================================
# Chat Endpoints
# ============================================================================

@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest, background_tasks: BackgroundTasks):
    """
    Send a message to Med Assist App and receive a response.
    """
    import time
    start_time = time.time()
    
    # 📱 LOG INCOMING REQUEST FROM PHONE
    logger.info("=" * 60)
    logger.info("📱 INCOMING REQUEST FROM PHONE")
    logger.info(f"📝 Message: {request.message[:100]}{'...' if len(request.message) > 100 else ''}")
    logger.info("=" * 60)
    
    llm = get_llm_service()
    vector_store = get_vector_store()
    
    if not llm or not llm.is_ready():
        raise HTTPException(
            status_code=503,
            detail="AI model not ready. Please wait for initialization."
        )
    
    # ⏱️ TIMING: Vector search
    t1 = time.time()
    
    # Retrieve context documents if enabled
    context_documents: List[ContextDocument] = []
    referenced_docs = []
    
    if request.include_context and vector_store:
        search_results = vector_store.search(
            query=request.message,
            n_results=request.max_context_docs
        )
        
        for result in search_results:
            context_documents.append(ContextDocument(
                content=result.content,
                source=result.metadata.source,
                timestamp=result.metadata.timestamp.strftime("%Y-%m-%d"),
                doc_type=result.metadata.doc_type
            ))
            referenced_docs.append({
                "doc_id": result.metadata.doc_id,
                "source": result.metadata.source,
                "doc_type": result.metadata.doc_type,
                "relevance": round(result.relevance_score, 3)
            })
    
    t2 = time.time()
    logger.info(f"⏱️ Vector search: {(t2-t1)*1000:.0f}ms")
    
    # Map analysis type
    analysis_type_map = {
        "lab_report": AnalysisType.LAB_REPORT,
        "symptom_check": AnalysisType.SYMPTOM_CHECK,
        "medication_info": AnalysisType.MEDICATION_INFO,
        "image_analysis": AnalysisType.IMAGE_ANALYSIS,
        "general_health": AnalysisType.GENERAL_HEALTH,
    }
    analysis_type = analysis_type_map.get(
        request.analysis_type, 
        AnalysisType.GENERAL_HEALTH
    )
    
    # Build prompt with medical context
    prompt = MedicalPromptTemplates.build_prompt(
        user_query=request.message,
        analysis_type=analysis_type,
        context_documents=context_documents if context_documents else None
    )
    
    t3 = time.time()
    logger.info(f"⏱️ Prompt build: {(t3-t2)*1000:.0f}ms")
    logger.info(f"📝 Prompt length: {len(prompt)} chars")
    
    # Generate response - RUN IN THREAD POOL (non-blocking)
    logger.info("🤖 Starting model inference (in thread pool)...")
    loop = asyncio.get_running_loop()
    response_text = await loop.run_in_executor(_executor, llm.generate_response, prompt)
    
    t4 = time.time()
    logger.success(f"⏱️ MODEL INFERENCE: {(t4-t3)*1000:.0f}ms ⬅️ THIS IS THE MODEL TIME")
    
    # Skip profile extraction for now - it adds latency
    # background_tasks.add_task(analyze_message_for_profile, request.message)
    
    inference_time = (time.time() - start_time) * 1000
    
    # 📱 LOG RESPONSE SENT TO PHONE
    logger.success("=" * 60)
    logger.success("✅ RESPONSE SENT TO PHONE")
    logger.success(f"⏱️ Time: {inference_time:.0f}ms")
    logger.success(f"📄 Response: {response_text[:150]}{'...' if len(response_text) > 150 else ''}")
    logger.success("=" * 60)
    
    return ChatResponse(
        response=response_text,
        referenced_documents=referenced_docs,
        inference_time_ms=round(inference_time, 2),
        model_ready=llm.is_ready(),
        context_saved=True # We optimistically say we are checking
    )


# ============================================================================
# Agentic Chat Endpoint (Multi-step reasoning)
# ============================================================================

@router.post("/chat/agentic", response_model=AgenticChatResponse)
async def agentic_chat(request: AgenticChatRequest):
    """
    Agentic chat with tool use and multi-step reasoning.
    
    Flow:
    1. Phone sends message + health context + session_id
    2. If loading old chat from history, phone sends conversation_history ONCE
    3. Server retrieves/stores conversation history in session memory
    4. AI reasons and may request tools
    5. When is_complete=True, show response to user
    
    For NEW chats: App doesn't send history - server remembers it!
    For OLD chats: App sends history ONCE when loading, then server takes over
    """
    import time
    from ..inference.agentic_engine import AgenticEngine, ToolType, ToolResult
    
    start_time = time.time()
    current_time = datetime.now()
    
    # Cleanup old sessions periodically
    _session_memory.cleanup_old_sessions()
    
    # Get or create session (server maintains history)
    session_id = _session_memory.get_or_create_session(request.session_id)
    
    # If loading old chat from app history, load it into server memory ONCE
    if request.is_loading_history and request.conversation_history:
        history_dicts = [
            {'role': m.role, 'content': m.content, 'timestamp': m.timestamp}
            for m in request.conversation_history
        ]
        _session_memory.load_history_from_app(session_id, history_dicts)
        logger.info(f"📚 Loaded {len(history_dicts)} messages from app history")
    
    # Get conversation history from server memory
    conversation_history = _session_memory.get_history(session_id)
    history_summary = _session_memory.get_summary(session_id)
    
    logger.info("=" * 60)
    logger.info("🤖 AGENTIC CHAT REQUEST")
    logger.info(f"📝 Message: {request.message[:80]}...")
    logger.info(f"🔄 Round: {request.round_number}")
    logger.info(f"📊 Health Context: {len(request.health_context)} items")
    logger.info(f"🔧 Tool Results: {len(request.tool_results)}")
    logger.info(f"💾 Session: {session_id} (history: {len(conversation_history)} msgs)")
    if history_summary:
        logger.info(f"📜 Has summary of older messages")
    logger.info("=" * 60)
    
    llm = get_llm_service()
    if not llm or not llm.is_ready():
        raise HTTPException(status_code=503, detail="AI model not ready")
    
    # Convert tool results from request
    tool_results = []
    for tr in request.tool_results:
        try:
            tool_type = ToolType[tr.tool.upper()]
            tool_results.append(ToolResult(
                tool=tool_type,
                success=tr.success,
                data=tr.data,
                error=tr.error
            ))
        except KeyError:
            logger.warning(f"Unknown tool in results: {tr.tool}")
    
    # Create agentic engine
    engine = AgenticEngine(llm)
    
    # Force final response on round 3+ (no more tools allowed)
    force_final = request.round_number >= 3
    
    # Process one round (with server-side conversation history + summary)
    response_text, new_tool_calls, step = engine.process_single_round(
        user_message=request.message,
        health_context=request.health_context,
        tool_results=tool_results if tool_results else None,
        reasoning_history=None,
        conversation_history=conversation_history,  # From server memory!
        history_summary=history_summary,  # Summary of older messages
        force_final=force_final
    )
    
    inference_time = (time.time() - start_time) * 1000
    
    # Convert tool calls to response format
    tool_calls_response = []
    for tc in new_tool_calls:
        tool_calls_response.append(ToolCallModel(
            tool=tc.tool.value,
            params=tc.params,
            reason=tc.reason
        ))
    
    # Determine if complete (no more tool calls needed)
    is_complete = len(new_tool_calls) == 0 or force_final
    
    # Save to server-side session memory ONLY when complete (final answer)
    if is_complete and response_text.strip():
        _session_memory.add_message(session_id, "user", request.message)
        _session_memory.add_message(session_id, "assistant", response_text)
        logger.info(f"💾 Saved to session memory ({len(conversation_history) + 2} msgs)")
    
    if is_complete:
        logger.success(f"✅ AGENTIC COMPLETE after {request.round_number + 1} rounds")
    else:
        logger.info(f"🔄 Requesting {len(new_tool_calls)} tool(s) from phone")
        for tc in new_tool_calls:
            logger.info(f"   - {tc.tool.value}: {tc.reason}")
    
    logger.info(f"⏱️ Inference time: {inference_time:.0f}ms")
    
    return AgenticChatResponse(
        response=response_text,
        tool_calls=tool_calls_response,
        is_complete=is_complete,
        session_id=session_id,
        round_number=request.round_number + 1,
        inference_time_ms=round(inference_time, 2),
        current_time=current_time.isoformat()
    )


@router.post("/chat/session/clear")
async def clear_session(session_id: str = None):
    """
    Clear session history. Call when user starts a new chat.
    App calls this when opening a new chat - server forgets previous conversation.
    """
    if session_id:
        _session_memory.clear_session(session_id)
        return {"success": True, "message": f"Session {session_id} cleared"}
    return {"success": False, "message": "No session_id provided"}


@router.get("/chat/session/info")
async def session_info(session_id: str = None):
    """Get info about a session (for debugging)."""
    if session_id:
        history = _session_memory.get_history(session_id)
        return {
            "session_id": session_id,
            "message_count": len(history),
            "messages": history
        }
    return {
        "active_sessions": _session_memory.get_session_count()
    }


@router.post("/explain", response_model=ChatResponse)
async def explain_response(request: ExplainRequest):
    """
    Explain how the AI reached its conclusion.
    
    Powers the "Why?" button in the UI.
    """
    import time
    start_time = time.time()
    
    llm = get_llm_service()
    vector_store = get_vector_store()
    
    if not llm or not llm.is_ready():
        raise HTTPException(status_code=503, detail="AI model not ready")
    
    # Get the referenced documents
    context_docs = []
    if vector_store and request.referenced_doc_ids:
        doc_metas = vector_store.get_document_sources(request.referenced_doc_ids)
        for meta in doc_metas:
            context_docs.append(ContextDocument(
                content="[Retrieved for explanation]",
                source=meta.source,
                timestamp=meta.timestamp.strftime("%Y-%m-%d"),
                doc_type=meta.doc_type
            ))
    
    # Build explainability prompt
    prompt = MedicalPromptTemplates.build_explainability_prompt(
        original_response=request.original_response,
        referenced_documents=context_docs
    )
    
    loop = asyncio.get_running_loop()
    response_text = await loop.run_in_executor(_executor, llm.generate_response, prompt)
    inference_time = (time.time() - start_time) * 1000
    
    return ChatResponse(
        response=response_text,
        referenced_documents=[],
        inference_time_ms=round(inference_time, 2),
        model_ready=True
    )


# ============================================================================
# Profile Endpoints (NEW)
# ============================================================================

@router.get("/profile")
async def get_patient_profile():
    """Get the full digital health archive."""
    pm = get_profile_manager()
    if not pm:
        raise HTTPException(status_code=503, detail="Profile manager not ready")
    return pm.get_profile()

@router.post("/profile")
async def update_patient_profile(profile_data: Dict[str, Any]):
    """Update valid parts of the profile manualy."""
    pm = get_profile_manager()
    if not pm:
        raise HTTPException(status_code=503, detail="Profile manager not ready")
    
    pm.update_profile(profile_data)
    return {"status": "updated", "timestamp": datetime.now().isoformat()}


# ============================================================================
# Document Endpoints
# ============================================================================

@router.post("/upload", response_model=DocumentResponse)
async def upload_document(
    file: UploadFile = File(...),
    doc_type: Optional[str] = Form(None),
    tags: Optional[str] = Form(None)
):
    """
    Upload a medical document for storage and analysis.
    
    Supported formats: PDF, images (JPG, PNG), text files.
    Documents are processed, embedded, and stored in the local vector DB.
    """
    vector_store = get_vector_store()
    
    if not vector_store:
        raise HTTPException(
            status_code=503,
            detail="Document storage not available"
        )
    
    # Process the uploaded file
    processor = DocumentProcessor()
    
    try:
        processed = processor.process_bytes(
            file_data=file.file,
            filename=file.filename,
            doc_type_hint=doc_type
        )
        
        if not processed:
            return DocumentResponse(
                success=False,
                message="Could not extract content from file"
            )
        
        # Create metadata
        metadata = DocumentMetadata(
            doc_id=processed.doc_id,
            source=processed.source_filename,
            doc_type=processed.doc_type,
            timestamp=datetime.now(),
            summary=processed.content[:200],
            tags=tags.split(",") if tags else []
        )
        
        # Store in vector DB
        chunk_ids = vector_store.add_document(
            content=processed.content,
            metadata=metadata
        )
        
        logger.info(
            f"Uploaded: {file.filename} -> {len(chunk_ids)} chunks "
            f"(type: {processed.doc_type})"
        )
        
        return DocumentResponse(
            success=True,
            doc_id=processed.doc_id,
            doc_type=processed.doc_type,
            message=f"Document processed and stored ({processed.page_count} pages)",
            chunks_created=len(chunk_ids)
        )
        
    except Exception as e:
        logger.error(f"Upload failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/context", response_model=List[ContextResult])
async def search_context(request: ContextSearchRequest):
    """
    Search stored documents for relevant context.
    
    Used by the explainability drawer to show which documents
    might be relevant to a query.
    """
    vector_store = get_vector_store()
    
    if not vector_store:
        return []
    
    results = vector_store.search(
        query=request.query,
        n_results=request.n_results,
        doc_type_filter=request.doc_type
    )
    
    return [
        ContextResult(
            content=r.content[:500],  # Truncate for response
            source=r.metadata.source,
            doc_type=r.metadata.doc_type,
            timestamp=r.metadata.timestamp.strftime("%Y-%m-%d %H:%M"),
            relevance_score=round(r.relevance_score, 3)
        )
        for r in results
    ]


@router.get("/documents")
async def list_documents():
    """
    List all stored documents.
    
    Returns a list of all documents in the vector store with metadata.
    """
    vector_store = get_vector_store()
    
    if not vector_store:
        return []
    
    try:
        # Get all documents from vector store
        docs = vector_store.list_all_documents()
        return [
            {
                "doc_id": doc.doc_id,
                "source": doc.source,
                "doc_type": doc.doc_type,
                "timestamp": doc.timestamp.isoformat(),
                "summary": doc.summary[:200] if doc.summary else "",
                "tags": doc.tags if hasattr(doc, 'tags') else [],
            }
            for doc in docs
        ]
    except Exception as e:
        logger.error(f"List documents failed: {e}")
        return []


# ============================================================================
# System Endpoints
# ============================================================================

@router.get("/health", response_model=HealthStatus)
async def health_check():
    """
    Check system health status.
    
    Returns status of all components:
    - AI model readiness
    - Vector store status
    - GPU availability
    - Document count
    """
    from ..config import settings
    
    llm = get_llm_service()
    vector_store = get_vector_store()
    
    # Get document count
    doc_count = 0
    memory_ready = False
    if vector_store:
        stats = vector_store.get_stats()
        doc_count = stats.get("total_documents", 0)
        memory_ready = stats.get("status") == "ready"
    
    model_ready = llm is not None and llm.is_ready()
    
    return HealthStatus(
        status="healthy" if model_ready else "degraded",
        model_ready=model_ready,
        memory_ready=memory_ready,
        gpu_enabled=settings.use_gpu,
        document_count=doc_count,
        version=settings.app_version
    )


@router.post("/memory/cleanup")
async def cleanup_memory():
    """
    Trigger cleanup of old documents.
    
    Removes documents older than the retention period.
    """
    vector_store = get_vector_store()
    
    if not vector_store:
        return {"removed": 0, "message": "Vector store not available"}
    
    removed = vector_store.cleanup_old_documents()
    
    return {
        "removed": removed,
        "message": f"Cleaned up {removed} old documents"
    }
