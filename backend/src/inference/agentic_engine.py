"""
Agentic AI Engine for Med Assist App
Enables AI to reason, query database, and save data autonomously.

Flow:
1. Phone sends message + initial health context
2. AI reasons and may request tool calls
3. Phone executes tools (DB queries, saves)
4. AI continues with results
5. Final response sent to user

This happens "under the hood" - user only sees final answer.
"""

import json
import re
from datetime import datetime
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional, Tuple
from enum import Enum
from loguru import logger


class ToolType(Enum):
    """Tools the AI can request."""
    QUERY_SYMPTOMS = "query_symptoms"      # Get active symptoms
    QUERY_CONDITIONS = "query_conditions"  # Get conditions
    QUERY_MEDICATIONS = "query_medications"  # Get medications
    QUERY_ALLERGIES = "query_allergies"    # Get allergies
    QUERY_HISTORY = "query_history"        # Get chat history
    SAVE_SYMPTOM = "save_symptom"          # Save new symptom
    SAVE_CONDITION = "save_condition"      # Save new condition
    SAVE_INSIGHT = "save_insight"          # Save AI insight
    RESOLVE_SYMPTOM = "resolve_symptom"    # Mark symptom resolved
    GET_TIME = "get_time"                  # Get current time
    SEARCH_PUBMED = "search_pubmed"        # Live medical database search
    SEARCH_CLINICAL_TRIALS = "search_clinical_trials" # Live trial search


@dataclass
class ToolCall:
    """A tool call request from the AI."""
    tool: ToolType
    params: Dict[str, Any] = field(default_factory=dict)
    reason: str = ""


@dataclass
class ToolResult:
    """Result from executing a tool on phone."""
    tool: ToolType
    success: bool
    data: Any
    error: Optional[str] = None


@dataclass
class ReasoningStep:
    """One step in the AI's reasoning process."""
    thought: str
    action: Optional[ToolCall] = None
    observation: Optional[str] = None


@dataclass
class AgenticResponse:
    """Complete response from the agentic engine."""
    final_response: str
    reasoning_steps: List[ReasoningStep]
    tool_calls: List[ToolCall]
    tool_results: List[ToolResult]
    total_tokens_used: int = 0
    reasoning_rounds: int = 0


class AgenticEngine:
    """
    Agentic reasoning engine for Med Assist App.
    
    The AI can:
    1. Think about what information it needs
    2. Request data from phone's database
    3. Save important insights
    4. Give final response after gathering all info
    """
    
    MAX_REASONING_ROUNDS = 3  # Prevent infinite loops
    
    def __init__(self, llm_service):
        self.llm = llm_service
    
    def _get_time_of_day(self, dt: datetime) -> str:
        """Get human-readable time of day."""
        hour = dt.hour
        if 5 <= hour < 12:
            return "Morning"
        elif 12 <= hour < 17:
            return "Afternoon"
        elif 17 <= hour < 21:
            return "Evening"
        else:
            return "Night"
    
    def build_agentic_prompt(
        self,
        user_message: str,
        health_context: Dict[str, Any],
        tool_results: List[ToolResult] = None,
        reasoning_history: List[ReasoningStep] = None,
        conversation_history: List[Dict[str, str]] = None,  # Recent chat history
        history_summary: str = None,  # Summary of older messages
        force_final: bool = False  # When True, don't allow more tool calls
    ) -> str:
        """Build prompt with time awareness, conversation history, and tool instructions."""
        
        # Get FRESH time for each request (not cached)
        now = datetime.now()
        time_info = f"""CURRENT TIME: {now.strftime('%Y-%m-%d %H:%M:%S')}
Day: {now.strftime('%A')}
Date: {now.strftime('%B %d, %Y')}
Time of day: {self._get_time_of_day(now)}"""
        
        # Build conversation history text
        conversation_text = ""
        if history_summary:
            conversation_text = f"\n\n{history_summary}"
        
        if conversation_history:
            recent = conversation_history[-6:]  # Keep last 6 exchanges
            history_lines = []
            for msg in recent:
                role = msg.get('role', 'user').upper()
                content = msg.get('content', '')[:300]  # Truncate long messages
                history_lines.append(f"{role}: {content}")
            if history_lines:
                conversation_text += "\n\nRECENT CONVERSATION:\n" + "\n".join(history_lines)
        
        # Health context summary
        context_parts = []
        if health_context.get('symptoms'):
            symptoms = health_context['symptoms']
            if symptoms:
                context_parts.append(f"Active Symptoms: {', '.join(s.get('name', 'Unknown') for s in symptoms)}")
        
        if health_context.get('conditions'):
            conditions = health_context['conditions']
            if conditions:
                context_parts.append(f"Conditions: {', '.join(c.get('name', 'Unknown') for c in conditions)}")
        
        if health_context.get('medications'):
            meds = health_context['medications']
            if meds:
                context_parts.append(f"Medications: {', '.join(m.get('name', 'Unknown') for m in meds)}")
        
        if health_context.get('allergies'):
            allergies = health_context['allergies']
            if allergies:
                context_parts.append(f"Allergies: {', '.join(a.get('allergen', 'Unknown') for a in allergies)}")
        
        health_summary = "\n".join(context_parts) if context_parts else "No health data recorded yet."
        
        # Tool results from previous rounds
        tool_results_text = ""
        if tool_results:
            results = []
            for tr in tool_results:
                if tr.success:
                    results.append(f"[{tr.tool.value}] Result: {json.dumps(tr.data, default=str)}")
                else:
                    results.append(f"[{tr.tool.value}] Error: {tr.error}")
            tool_results_text = "\n\nPREVIOUS TOOL RESULTS:\n" + "\n".join(results)
        
        # Reasoning history
        reasoning_text = ""
        if reasoning_history:
            steps = []
            for i, step in enumerate(reasoning_history, 1):
                steps.append(f"Step {i} - Thought: {step.thought}")
                if step.observation:
                    steps.append(f"  Observation: {step.observation}")
            reasoning_text = "\n\nYOUR PREVIOUS REASONING:\n" + "\n".join(steps)
        
        # If force_final, don't show tool options - just ask for direct answer
        if force_final:
            prompt = f"""You are Med Assist App, a helpful and thorough medical AI assistant.

{time_info}
{conversation_text}

USER'S HEALTH CONTEXT:
{health_summary}
{tool_results_text}

CURRENT USER MESSAGE: {user_message}

IMPORTANT: Give a direct, helpful response NOW. Do not request any tools. 
Based on the conversation and information above, provide your best medical advice.

RESPONSE GUIDELINES:
- Be thorough and detailed in your explanations
- If discussing symptoms, explain possible causes and what to watch for
- Provide actionable advice when appropriate
- Use bullet points or numbered lists for clarity when helpful
- Be empathetic and supportive
- Always recommend consulting a doctor for serious or persistent concerns
- Do NOT be overly brief - provide comprehensive information that helps the user understand their situation

YOUR RESPONSE:"""
            return prompt
        
        prompt = f"""You are Med Assist App, a helpful and thorough medical AI assistant with access to the user's health database.

{time_info}
{conversation_text}

USER'S HEALTH CONTEXT:
{health_summary}
{tool_results_text}
{reasoning_text}

AVAILABLE TOOLS (use only if needed):
- QUERY_SYMPTOMS: Get all active symptoms with details
- QUERY_CONDITIONS: Get medical conditions history
- QUERY_MEDICATIONS: Get current and past medications
- QUERY_ALLERGIES: Get allergy information
- SAVE_SYMPTOM: Save a new symptom (params: name, severity, notes)
- SAVE_INSIGHT: Save an important health insight (params: insight, category)
- RESOLVE_SYMPTOM: Mark a symptom as resolved (params: name)
- SEARCH_PUBMED: Search live medical literature for rare diseases, drugs, or novel conditions (params: query)
- SEARCH_CLINICAL_TRIALS: Search live clinical trials for a specific condition (params: condition)

HOW TO USE TOOLS:
If you need more information, respond with:
<TOOL>tool_name|param1=value1|param2=value2</TOOL>
<REASON>why you need this</REASON>

If you want to save something important:
<TOOL>SAVE_SYMPTOM|name=Headache|severity=moderate|notes=started after lunch</TOOL>
<REASON>User mentioned new symptom</REASON>

If you are asked about a complex medical topic or recent drug/trial:
<TOOL>SEARCH_PUBMED|query=Type 1 Diabetes breakthrough</TOOL>
<REASON>Need recent literature to answer</REASON>

RULES:
1. Only use tools if you actually need more info
2. After getting tool results, give your FINAL answer
3. Be THOROUGH and DETAILED - explain concepts clearly
4. Use bullet points or numbered lists when appropriate
5. For serious symptoms, always recommend seeing a doctor
6. If user mentions new symptoms, save them
7. Be aware of the current time when discussing medications/schedules
8. Provide comprehensive information - not just brief responses
9. Be empathetic and supportive in your tone

USER MESSAGE: {user_message}

If you have enough information, respond directly with a detailed, helpful answer. If you need to query or save data, use the TOOL format above.

YOUR RESPONSE:"""
        
        return prompt
    
    def parse_tool_calls(self, response: str) -> Tuple[str, List[ToolCall]]:
        """Parse tool calls from AI response."""
        tool_calls = []
        clean_response = response
        
        # Find all tool calls
        tool_pattern = r'<TOOL>([^<]+)</TOOL>'
        reason_pattern = r'<REASON>([^<]+)</REASON>'
        
        tool_matches = re.findall(tool_pattern, response)
        reason_matches = re.findall(reason_pattern, response)
        
        for i, tool_str in enumerate(tool_matches):
            parts = tool_str.strip().split('|')
            if not parts:
                continue
            
            tool_name = parts[0].strip().upper()
            params = {}
            
            # Parse parameters
            for param in parts[1:]:
                if '=' in param:
                    key, value = param.split('=', 1)
                    params[key.strip()] = value.strip()
            
            # Map to ToolType
            try:
                tool_type = ToolType[tool_name]
                reason = reason_matches[i] if i < len(reason_matches) else ""
                tool_calls.append(ToolCall(tool=tool_type, params=params, reason=reason))
            except KeyError:
                logger.warning(f"Unknown tool requested: {tool_name}")
        
        # Remove tool tags from response
        clean_response = re.sub(r'<TOOL>[^<]+</TOOL>', '', clean_response)
        clean_response = re.sub(r'<REASON>[^<]+</REASON>', '', clean_response)
        clean_response = clean_response.strip()
        
        return clean_response, tool_calls
    
    def process_single_round(
        self,
        user_message: str,
        health_context: Dict[str, Any],
        tool_results: List[ToolResult] = None,
        reasoning_history: List[ReasoningStep] = None,
        conversation_history: List[Dict[str, str]] = None,  # Recent chat history
        history_summary: str = None,  # Summary of older messages
        force_final: bool = False
    ) -> Tuple[str, List[ToolCall], ReasoningStep]:
        """Process one round of reasoning."""
        
        prompt = self.build_agentic_prompt(
            user_message=user_message,
            health_context=health_context,
            tool_results=tool_results,
            reasoning_history=reasoning_history,
            conversation_history=conversation_history,
            history_summary=history_summary,
            force_final=force_final
        )
        
        # Generate response
        raw_response = self.llm.generate_response(prompt)
        
        # Parse for tool calls (if force_final, ignore any tool calls)
        clean_response, tool_calls = self.parse_tool_calls(raw_response)
        if force_final:
            tool_calls = []  # No more tools allowed
        
        # Create reasoning step
        step = ReasoningStep(
            thought=f"Processing: {user_message[:50]}...",
            action=tool_calls[0] if tool_calls else None,
            observation=clean_response[:200] if clean_response else None
        )
        
        return clean_response, tool_calls, step


class AgenticRequest:
    """Request format for agentic processing."""
    def __init__(
        self,
        message: str,
        health_context: Dict[str, Any] = None,
        pending_tool_results: List[Dict] = None,
        session_id: str = None
    ):
        self.message = message
        self.health_context = health_context or {}
        self.pending_tool_results = pending_tool_results or []
        self.session_id = session_id or datetime.now().strftime("%Y%m%d%H%M%S")


class AgenticSession:
    """Manages an agentic reasoning session."""
    
    def __init__(self):
        self.reasoning_steps: List[ReasoningStep] = []
        self.tool_calls: List[ToolCall] = []
        self.tool_results: List[ToolResult] = []
        self.rounds: int = 0
        self.is_complete: bool = False
        self.final_response: str = ""
