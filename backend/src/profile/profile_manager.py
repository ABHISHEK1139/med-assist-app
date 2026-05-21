import json
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field
from loguru import logger

from ..inference.llm_service import LLMService

class MedicalEntity(BaseModel):
    """A single medical fact extracted from text."""
    category: str  # Condition, Medication, Allergy, Surgery, Vitals, Lifestyle
    name: str      # e.g., "Asthma", "Lisinopril"
    status: str    # Active, Past, Unknown
    onset_date: Optional[str] = None  # YYYY, YYYY-MM, or YYYY-MM-DD
    notes: Optional[str] = None

class PatientProfile(BaseModel):
    """The full digital health archive."""
    conditions: List[MedicalEntity] = []
    medications: List[MedicalEntity] = []
    allergies: List[MedicalEntity] = []
    surgeries: List[MedicalEntity] = []
    lifestyle: List[MedicalEntity] = []
    vitals: List[MedicalEntity] = []
    last_updated: str = Field(default_factory=lambda: datetime.now().isoformat())

class ProfileManager:
    """
    Manages the Digital Health Archive.
    - Persists profile to JSON.
    - run_extraction: Passive analysis of chat messages.
    """
    
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.profile_path = data_dir / "patient_profile.json"
        
        # Ensure data dir exists
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.profile = self._load_profile()
        
    def _load_profile(self) -> PatientProfile:
        if not self.profile_path.exists():
            return PatientProfile()
        
        try:
            with open(self.profile_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return PatientProfile(**data)
        except Exception as e:
            logger.error(f"Failed to load profile: {e}")
            return PatientProfile()

    def _save_profile(self):
        try:
            with open(self.profile_path, "w", encoding="utf-8") as f:
                json.dump(self.profile.model_dump(), f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save profile: {e}")

    def get_profile(self) -> dict:
        return self.profile.model_dump()

    def update_profile(self, new_data: dict):
        """Manual update from UI."""
        # Simple merge strategy for now: Overwrite logic would be complex
        # Here we just replace lists if provided
        updated = False
        for key in ["conditions", "medications", "allergies", "surgeries", "lifestyle", "vitals"]:
            if key in new_data:
                # Convert raw dicts back to Pydantic models
                entities = [MedicalEntity(**item) for item in new_data[key]]
                setattr(self.profile, key, entities)
                updated = True
        
        if updated:
            self.profile.last_updated = datetime.now().isoformat()
            self._save_profile()
            
    async def extract_from_message(self, message: str, llm: LLMService) -> bool:
        """
        Passive extraction. 
        Returns True if new info was discovered and saved.
        """
        if not llm or not llm.is_ready():
            return False
            
        # 1. Prompt Engineering
        # We ask the LLM to output ONLY JSON if it finds medical facts.
        prompt = f"""
Analyze this user message for personal medical history. 
User Message: "{message}"

Current Year: {datetime.now().year}

If the user mentions:
- Chronic Conditions (e.g. "I have diabetes")
- Past Surgeries
- Medications (Current or Past)
- Allergies
- Lifestyle (Smoking, Alcohol, etc.)

Extract them into this JSON format. Calculate years for "X years ago".
{{
  "entities": [
    {{
      "category": "Condition" | "Medication" | "Allergy" | "Surgery" | "Lifestyle",
      "name": "Standardized Name",
      "status": "Active" | "Past",
      "onset_date": "YYYY" (Calculate from '10 years ago' etc),
      "notes": "Original text context"
    }}
  ]
}}

If NO medical history facts are present, output: {{ "entities": [] }}
Return ONLY JSON. Do not explain.
"""
        
        try:
            # 2. Run Inference (this might need to be optimized for speed/concurrency)
            import asyncio
            loop = asyncio.get_running_loop()
            response = await loop.run_in_executor(None, llm.generate_response, prompt)
            
            # 3. Parse JSON
            # Clean possible markdown code blocks
            json_str = response.replace("```json", "").replace("```", "").strip()
            # Find the first { and last }
            start = json_str.find("{")
            end = json_str.rfind("}") + 1
            if start == -1 or end == 0:
                return False
                
            data = json.loads(json_str[start:end])
            entities = data.get("entities", [])
            
            if not entities:
                return False
                
            # 4. Integrate into Profile
            count = 0
            for item in entities:
                entity = MedicalEntity(**item)
                # Naive Append Strategy: Just add to the correct list
                # (In production, we'd check for duplicates)
                # Map category names to profile field names
                category_to_field = {
                    "condition": "conditions",
                    "medication": "medications",
                    "allergy": "allergies",
                    "surgery": "surgeries",
                    "lifestyle": "lifestyle",
                    "vitals": "vitals",
                }
                field_name = category_to_field.get(entity.category.lower())
                target_list = getattr(self.profile, field_name, None) if field_name else None
                if target_list is None:
                    # Handle Vitals/Lifestyle mapping if naming differs
                    if entity.category == "Lifestyle": target_list = self.profile.lifestyle
                    elif entity.category == "Vitals": target_list = self.profile.vitals
                    # Default map
                    elif entity.category == "Condition": target_list = self.profile.conditions
                    elif entity.category == "Medication": target_list = self.profile.medications
                    elif entity.category == "Allergy": target_list = self.profile.allergies
                    elif entity.category == "Surgery": target_list = self.profile.surgeries
                
                if target_list is not None:
                    # Check for Exact Name Duplicates to avoid spamming
                    if not any(e.name.lower() == entity.name.lower() for e in target_list):
                        target_list.append(entity)
                        count += 1
            
            if count > 0:
                self.profile.last_updated = datetime.now().isoformat()
                self._save_profile()
                logger.info(f"Extracted {count} new medical entities from chat")
                return True
                
        except Exception as e:
            logger.warning(f"Extraction failed: {e}")
            
        return False
