from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel
import shutil
import os
from PIL import Image
from sympy import sympify, solve, Symbol, Eq, parse_expr, latex
from sympy.parsing.sympy_parser import standard_transformations, implicit_multiplication_application
import google.generativeai as genai
from pathlib import Path # <--- Import Path
import certifi
from bson import ObjectId

# --- DB IMPORTS ---
from motor.motor_asyncio import AsyncIOMotorClient
from datetime import datetime
from dotenv import load_dotenv # Make sure you have python-dotenv installed

# 1. Explicitly find the path to the .env file in the current folder
env_path = Path(__file__).parent / ".env"

# 2. Load that specific file
load_dotenv(dotenv_path=env_path)

# 3. Now get the key
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
MONGO_URL = os.getenv("MONGO_URL")

if not GOOGLE_API_KEY:
    raise ValueError(f"No API key found. Please ensure '{env_path}' exists and contains GOOGLE_API_KEY.")

import google.generativeai as genai
genai.configure(api_key=GOOGLE_API_KEY)

genai.configure(api_key=GOOGLE_API_KEY)
app = FastAPI()

# --- DATABASE SETUP ---
client = AsyncIOMotorClient(MONGO_URL, tlsCAFile=certifi.where())
db = client.math_solver_db # This creates a DB named 'math_solver_db'
history_collection = db.history # This creates a collection named 'history

class MathRequest(BaseModel):
    equation: str

class HistoryItem(BaseModel):
    equation: str
    solution: str = None     # Changed to optional (None) because "Hint" mode won't have a solution yet
    explanation: str = None  # Changed to optional
    timestamp: str = None
    chat_history: list = []  # <--- NEW: Stores the chat logs

class ChatRequest(BaseModel):
    context: str  # The original math problem + solution
    history: list # List of previous Q&A e.g. [{"role": "user", "parts": ["hi"]}]
    message: str  # The new question


# --- ENDPOINTS ---

@app.get("/")
def read_root():
    return {"status": "Server is running", "db_status": "Connected to MongoDB"}

# --- ENDPOINT 1: EXTRACT TEXT (OCR) ---
@app.post("/api/extract")
async def extract_from_image(file: UploadFile = File(...)):
    os.makedirs("uploads", exist_ok=True)
    file_path = f"uploads/{file.filename}"
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    try:
        # Changed: Now extracts FULL text, not just equation
        extracted_text = image_to_full_text(file_path) 
        return {"equation": extracted_text}
    except Exception as e:
        return {"error": str(e)}

# --- ENDPOINT 2: SOLVE (Calculator + AI Logic) ---
@app.post("/api/calculate")
async def calculate_solution(request: MathRequest):
    problem_text = request.equation
    
    solution_result = None
    
    # 1. Try SymPy first (Good for simple x + y = z)
    try:
        cleaned_equation = sanitize_for_sympy(problem_text)
        solution_result = solve_with_sympy(cleaned_equation)
    except Exception:
        solution_result = None 

    # 2. If SymPy failed, use AI to get the FINAL ANSWER
    if solution_result is None or solution_result == "[]":
        try:
            # New function to get just the result in LaTeX
            solution_result = solve_final_answer_with_ai(problem_text)
        except Exception as e:
            solution_result = r"\text{Error generating solution}"

    # 3. Generate Full Explanation
    explanation = "Explanation unavailable."
    try:
        explanation = generate_explanation(problem_text, solution_result)
    except Exception as e:
        explanation = f"Explanation Error: {e}"
        
    return {
        "solution": str(solution_result),
        "explanation": explanation
    }

# 3. SAVE HISTORY (New!)
@app.post("/api/history")
async def save_history(item: HistoryItem):
    try:
        # Add current time
        item.timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
        # Insert into MongoDB
        await history_collection.insert_one(item.dict())
        return {"message": "Saved to History"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 4. GET HISTORY (New!)
@app.get("/api/history")
async def get_history():
    try:
        # Fetch latest 20 items, sorted by newest
        history_list = []
        cursor = history_collection.find({}).sort("_id", -1).limit(20)
        async for document in cursor:
            # Convert ObjectId to string for JSON compatibility
            document["_id"] = str(document["_id"])
            history_list.append(document)
        return history_list
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
# 5. CHAT WITH AI TUTOR (New!)
@app.post("/api/chat")
async def chat_with_tutor(request: ChatRequest):
    try:
        model = genai.GenerativeModel('models/gemini-2.5-flash')
        
        # Construct the "System Prompt" to give the AI context
        # We tell it: "You are a tutor. Here is the problem the student is looking at..."
        system_instruction = f"""
        You are a helpful math tutor. The student is asking questions about this specific problem:
        
        CONTEXT:
        {request.context}
        
        RULES:
        1. Answer the student's question clearly.
        2. Use the Context above to be specific.
        3. Be concise (max 2-3 sentences unless asked for more).
        4. Use LaTeX for math equations (wrapped in single $).
        """
        
        # Build the chat history for Gemini
        chat = model.start_chat(history=request.history)
        
        # Send the message with the system instruction prepended (soft-prompting)
        full_prompt = f"{system_instruction}\n\nStudent Question: {request.message}"
        
        response = chat.send_message(full_prompt)
        
        return {"reply": response.text.replace("$$", "$")} # Clean LaTeX
        
    except Exception as e:
        return {"error": str(e)}
    
# 6. UPDATE HISTORY (Append Chat Messages)
class ChatUpdate(BaseModel):
    chat_history: list

@app.put("/api/history/{id}")
async def update_history_chat(id: str, update: ChatUpdate):
    try:
        # Update the specific document with the new chat history
        result = await history_collection.update_one(
            {"_id": ObjectId(id)},
            {"$set": {"chat_history": update.chat_history}}
        )
        if result.matched_count == 0:
            raise HTTPException(status_code=404, detail="History item not found")
        return {"message": "Chat updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))   
 
# --- HELPER FUNCTIONS ---

def image_to_full_text(image_path):
    """Extracts ALL text for context (Word problems, Signals, etc.)"""
    model = genai.GenerativeModel('models/gemini-2.5-flash')
    img = Image.open(image_path)
    prompt = """
    Extract the full math problem from this image.
    Include the main equation and any context (like "Find the impulse response").
    Return plain text.
    """
    response = model.generate_content([prompt, img])
    return response.text.strip()

def sanitize_for_sympy(equation):
    # Basic cleanup for simple algebra
    equation = equation.replace("$", "").replace(r"\(", "").replace(r"\)", "")
    equation = equation.replace("^", "**").replace(r"\times", "*")
    return equation

def solve_with_sympy(equation_str):
    # (Same logic as before - good for Algebra I/II)
    x = Symbol('x')
    transformations = (standard_transformations + (implicit_multiplication_application,))
    if "=" in equation_str:
        parts = equation_str.split("=")
        lhs = parse_expr(parts[0], transformations=transformations)
        rhs = parse_expr(parts[1], transformations=transformations)
        eqn = Eq(lhs, rhs)
        result = solve(eqn, x)
        return latex(result)
    else:
        return None # Skip expressions for now, let AI handle them

def solve_final_answer_with_ai(problem_text):
    model = genai.GenerativeModel('models/gemini-2.5-flash')
    
    # Corrected Prompt
    prompt = f"""
    Solve this math problem: "{problem_text}"
    
    I need ONLY the final answer to display in a result card.
    
    RULES:
    1. Return ONLY the math result in LaTeX.
    2. Do NOT use dollar signs ($).
    3. If there are multiple parts (e.g., H(z) AND h[n]), separate them with a double backslash (\\\\).
       Example Output: H(z) = \\frac{{1}}{{1-z^{{-1}}}} \\\\ h[n] = u[n]
    """
    
    response = model.generate_content(prompt)
    
    # Cleanup
    clean = response.text.replace("```latex", "").replace("```", "").replace("$$", "").replace("$", "")
    return clean.strip()

def generate_explanation(equation, solution):
    model = genai.GenerativeModel('models/gemini-2.5-flash')
    
    prompt = f"""
    You are a math tutor. Problem: "{equation}". 
    
    Explain the solution step-by-step.
    
    STRICT FORMATTING RULES:
    1. Do NOT use bullet points (no *, no -). Write in full paragraphs.
    2. Use **bold** for Step titles (e.g., **Step 1:**).
    3. Start every new step on a new line.
    4. Use LaTeX for math, wrapped in single dollar signs ($).
    5. Do NOT use Markdown Headers (###).
    6. Do NOT add extra asterisks on their own lines.
    """
    
    response = model.generate_content(prompt)
    
    text = response.text
    
    # --- ROBUST CLEANUP ---
    # 1. Fix LaTeX double dollars
    text = text.replace("$$", "$")
    
    # 2. Remove Markdown Headers
    text = text.replace("### ", "").replace("## ", "").replace("# ", "")
    
    # 3. Remove stray bullet points/asterisks that cause weird indentation
    text = text.replace("\n* ", "\n").replace("\n- ", "\n")
    text = text.replace("\n * ", "\n") # Indented bullets
    
    # 4. Remove the specific "lone asterisk" artifact you saw
    text = text.replace("\n*\n", "\n")
    
    return text.strip()
    return text