import asyncio
from typing import Dict, Any, List, Tuple
from loguru import logger
from .llm_service import LLMService

class MultiAgentEngine:
    """
    Orchestrates a multi-agent consultation room.
    1. Diagnostician: Analyzes symptoms.
    2. Pharmacist: Checks drug interactions.
    3. Lead Physician: Synthesizes both and answers user.
    """
    
    def __init__(self, llm_service: LLMService):
        self.llm = llm_service

    async def run_consultation(
        self, 
        user_message: str, 
        health_context: Dict[str, Any]
    ) -> Tuple[str, List[Dict[str, str]]]:
        """
        Runs the consultation pipeline.
        Returns the final response and a list of reasoning steps from the agents.
        """
        logger.info("🏛️ Starting Multi-Agent Consultation Room")
        
        # Format context
        context_str = str(health_context) if health_context else "No prior health context."

        # Agent 1: Diagnostician
        prompt_1 = f"""You are the Expert Diagnostician. 
Review the following patient context and current query. Focus ONLY on potential underlying conditions, red flag symptoms, and differential diagnoses. Be analytical.

Patient Context: {context_str}
Patient Query: "{user_message}"

Your Diagnostic Assessment:"""

        logger.info("👨‍⚕️ Running Diagnostician...")
        loop = asyncio.get_running_loop()
        diag_resp = await loop.run_in_executor(None, self.llm.generate_response, prompt_1)
        
        # Agent 2: Pharmacist
        prompt_2 = f"""You are the Clinical Pharmacist.
Review the following patient context and current query. Focus ONLY on drug-drug interactions, side effects, contraindications, and dosage issues based on their medications. Be precise.

Patient Context: {context_str}
Patient Query: "{user_message}"

Your Pharmacological Assessment:"""

        logger.info("💊 Running Pharmacist...")
        pharm_resp = await loop.run_in_executor(None, self.llm.generate_response, prompt_2)
        
        # Agent 3: Lead Physician
        prompt_3 = f"""You are the Lead Physician.
You are running a consultation board. The patient has asked a question.
Read the patient's context, the Diagnostician's notes, and the Pharmacist's notes.
Synthesize this information into a cohesive, empathetic, and highly detailed final response for the patient. Do not contradict yourself. Provide clear, actionable advice.

Patient Context: {context_str}
Patient Query: "{user_message}"

--- Diagnostician's Notes ---
{diag_resp}

--- Pharmacist's Notes ---
{pharm_resp}

Your Final Response to Patient:"""

        logger.info("🩺 Running Lead Physician...")
        final_resp = await loop.run_in_executor(None, self.llm.generate_response, prompt_3)
        
        reasoning_steps = [
            {"agent": "Diagnostician", "thought": diag_resp},
            {"agent": "Pharmacist", "thought": pharm_resp},
        ]
        
        return final_resp, reasoning_steps
