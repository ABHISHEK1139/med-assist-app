"""
Med Assist App Medical Prompt Templates
Structured prompts optimized for medical analysis.

GDPR-Compliant Architecture:
- User's phone stores all health data
- PC processes AI requests but stores nothing
- AI can REQUEST storage on phone (phone decides)

These templates work identically on PC and mobile - just copy them
to your Kotlin resources when porting.
"""

from dataclasses import dataclass
from typing import Optional, List
from enum import Enum


class AnalysisType(Enum):
    """Types of medical analysis the AI can perform."""
    LAB_REPORT = "lab_report"
    SYMPTOM_CHECK = "symptom_check"
    MEDICATION_INFO = "medication_info"
    GENERAL_HEALTH = "general_health"
    IMAGE_ANALYSIS = "image_analysis"
    HEALTH_WITH_CONTEXT = "health_with_context"


@dataclass
class ContextDocument:
    """A document retrieved from the memory/RAG system."""
    content: str
    source: str
    timestamp: str
    doc_type: str


class MedicalPromptTemplates:
    """
    Prompt engineering templates for Med Assist App.
    SIMPLIFIED for faster inference.
    """
    
    # Minimal system prompt for speed
    SYSTEM_PREFIX = """You are Med Assist App, a helpful medical AI assistant. Be concise and helpful. Always recommend consulting doctors for serious concerns."""

    # Disabled for speed - can enable later
    AI_MEMORY_INSTRUCTIONS = ""

    SAFETY_SUFFIX = ""

    @classmethod
    def build_prompt(
        cls,
        user_query: str,
        analysis_type: AnalysisType = AnalysisType.GENERAL_HEALTH,
        context_documents: Optional[List[ContextDocument]] = None,
        include_system_prompt: bool = True,
        enable_memory_commands: bool = False  # Disabled by default for speed
    ) -> str:
        """
        Build a prompt with medical context for inference.
        """
        parts = []
        
        if include_system_prompt:
            parts.append(cls.SYSTEM_PREFIX)
        
        # Add task-specific instruction
        task_instruction = cls._get_task_instruction(analysis_type)
        parts.append(f"\nTask: {task_instruction}")
        
        # Inject RAG context documents if provided
        if context_documents:
            parts.append("\n=== RELEVANT HEALTH DOCUMENTS ===")
            for doc in context_documents:
                parts.append(f"- [{doc.doc_type}] {doc.source} ({doc.timestamp}): {doc.content[:500]}")
            parts.append("=================================\n")
        
        if enable_memory_commands and cls.AI_MEMORY_INSTRUCTIONS:
            parts.append(cls.AI_MEMORY_INSTRUCTIONS)
        
        parts.append(f"\nUser: {user_query}")
        parts.append("\nAssistant:")
        
        return "\n".join(parts)
    
    @classmethod
    def _get_task_instruction(cls, analysis_type: AnalysisType) -> str:
        """Get task-specific instructions based on analysis type."""
        instructions = {
            AnalysisType.LAB_REPORT: (
                "Analyze the provided lab values. Identify any values outside "
                "normal ranges, explain their significance, and suggest follow-up "
                "questions for a healthcare provider."
            ),
            AnalysisType.SYMPTOM_CHECK: (
                "Based on the described symptoms, provide possible explanations "
                "(not diagnoses), suggest when to seek immediate care, and "
                "recommend relevant questions to ask a doctor."
            ),
            AnalysisType.MEDICATION_INFO: (
                "Provide information about the mentioned medication including "
                "common uses, potential side effects, and important interactions. "
                "Always recommend verifying with a pharmacist."
            ),
            AnalysisType.GENERAL_HEALTH: (
                "Provide helpful health information based on the query. Be "
                "informative while emphasizing the importance of professional "
                "medical advice for personal health decisions."
            ),
            AnalysisType.IMAGE_ANALYSIS: (
                "Analyze the provided medical image description. Note visible "
                "characteristics and suggest what a healthcare provider might "
                "want to examine further. Do not provide diagnoses."
            ),
            AnalysisType.HEALTH_WITH_CONTEXT: (
                "Respond to the health query using the provided context. "
                "If you notice patterns or important insights, use storage "
                "commands to remember them. Be conversational and helpful."
            ),
        }
        return instructions.get(
            analysis_type, 
            instructions[AnalysisType.GENERAL_HEALTH]
        )
    
    @classmethod
    def build_explainability_prompt(
        cls,
        original_response: str,
        referenced_documents: List[ContextDocument]
    ) -> str:
        """
        Build a prompt to explain how the AI reached its conclusion.
        
        This powers the "Why?" button in the UI.
        """
        doc_summaries = "\n".join([
            f"- {doc.source} ({doc.timestamp}): {doc.content[:100]}..."
            for doc in referenced_documents
        ])
        
        return f"""Based on your previous response:

"{original_response[:300]}..."

The following documents from the user's health history were referenced:
{doc_summaries}

Explain briefly:
1. Which specific information from these documents influenced your response
2. How each piece of evidence contributed to your analysis
3. What information you did NOT have that might change your analysis

Keep the explanation concise and user-friendly."""

    @classmethod
    def build_rag_query(cls, user_query: str) -> str:
        """
        Transform user query for optimal vector search.
        
        This helps ChromaDB find the most relevant documents.
        """
        return f"""Find health documents related to: {user_query}
        
Focus on:
- Lab results with relevant biomarkers
- Previous similar symptoms or conditions
- Medication history if relevant
- Recent health records (prefer newer documents)"""
