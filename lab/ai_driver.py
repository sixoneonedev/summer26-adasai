import requests
import json
import os

# ═══════════════════════════════════════
#   SET THIS TO INSTRUCTOR PROVIDED IP
OLLAMA_HOST = os.environ.get('OLLAMA_HOST', '192.168.4.44')   # set automatically by deploy/deploy_to_kits.sh, or export OLLAMA_HOST yourself
OLLAMA_PORT = 11434
MODEL       = "phi3:mini"
# ═══════════════════════════════════════

DEFAULT_SYSTEM_PROMPT = """You are the AI brain of a small robot car following a colored target.
Respond with ONLY one word: FORWARD, LEFT, RIGHT, or STOP.
No explanation. No punctuation. Just the single word."""


def ask(prompt, host=OLLAMA_HOST):
    """Send a prompt to Ollama and return the response text."""
    try:
        response = requests.post(
            f"http://{host}:{OLLAMA_PORT}/api/generate",
            json={
                "model": MODEL,
                "prompt": prompt,
                "stream": False
            },
            timeout=30
        )
        return response.json()["response"]
    except Exception as e:
        return f"ERROR: Could not reach AI server -- {str(e)}"

def decide(observation, system_prompt=DEFAULT_SYSTEM_PROMPT):
    """Given an observation, get a driving decision."""
    prompt = f"{system_prompt}\n\nObservation: {observation}"
    response = ask(prompt).strip().upper()
    # extract first valid command in case model ignores constraints
    for word in response.split():
        if word in ['FORWARD', 'LEFT', 'RIGHT', 'STOP']:
            return word
    return 'STOP'  # safe default