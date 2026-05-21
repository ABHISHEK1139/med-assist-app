import requests
from loguru import logger
from typing import Dict, Any, List

def search_pubmed(query: str, max_results: int = 3) -> Dict[str, Any]:
    """Search PubMed using NCBI E-utilities."""
    logger.info(f"🔍 Searching PubMed for: {query}")
    try:
        # Step 1: Search
        search_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
        search_params = {
            "db": "pubmed",
            "term": query,
            "retmode": "json",
            "retmax": max_results
        }
        search_res = requests.get(search_url, params=search_params, timeout=10)
        search_res.raise_for_status()
        search_data = search_res.json()
        
        id_list = search_data.get("esearchresult", {}).get("idlist", [])
        if not id_list:
            return {"status": "success", "results": "No results found."}
            
        # Step 2: Fetch summaries
        summary_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
        summary_params = {
            "db": "pubmed",
            "id": ",".join(id_list),
            "retmode": "json"
        }
        summary_res = requests.get(summary_url, params=summary_params, timeout=10)
        summary_res.raise_for_status()
        summary_data = summary_res.json().get("result", {})
        
        results = []
        for uid in id_list:
            doc = summary_data.get(uid, {})
            title = doc.get("title", "")
            pubdate = doc.get("pubdate", "")
            source = doc.get("source", "")
            results.append(f"[{uid}] {title} ({source}, {pubdate})")
            
        return {"status": "success", "results": "\n".join(results)}
    except Exception as e:
        logger.error(f"PubMed search failed: {e}")
        return {"status": "error", "message": str(e)}

def search_clinical_trials(condition: str, max_results: int = 3) -> Dict[str, Any]:
    """Search ClinicalTrials.gov API v2."""
    logger.info(f"🔍 Searching ClinicalTrials.gov for: {condition}")
    try:
        url = "https://clinicaltrials.gov/api/v2/studies"
        params = {
            "query.cond": condition,
            "pageSize": max_results,
            "sort": "@relevance"
        }
        res = requests.get(url, params=params, timeout=10)
        res.raise_for_status()
        data = res.json()
        
        studies = data.get("studies", [])
        if not studies:
            return {"status": "success", "results": "No trials found."}
            
        results = []
        for study in studies:
            protocol = study.get("protocolSection", {})
            ident = protocol.get("identificationModule", {})
            status = protocol.get("statusModule", {})
            nct_id = ident.get("nctId", "Unknown NCT")
            title = ident.get("briefTitle", "No Title")
            overall_status = status.get("overallStatus", "Unknown Status")
            results.append(f"[{nct_id}] {title} (Status: {overall_status})")
            
        return {"status": "success", "results": "\n".join(results)}
    except Exception as e:
        logger.error(f"ClinicalTrials search failed: {e}")
        return {"status": "error", "message": str(e)}
