from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel
import shutil
import os
import json
from PIL import Image
# --- DB IMPORTS ---
from motor.motor_asyncio import AsyncIOMotorClient
import certifi
from dotenv import load_dotenv 
import google.generativeai as genai
from groq import Groq  # <-- NEW IMPORT
from sympy import sympify, solve, Symbol, Eq, parse_expr, latex
from sympy.parsing.sympy_parser import standard_transformations, implicit_multiplication_application
from datetime import datetime, timezone
# Load Env
load_dotenv()

# --- CONFIGURATION ---
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY") # Get Groq Key
MONGO_URL = os.getenv("MONGO_URL")

# 1. Setup Gemini (Eyes)
genai.configure(api_key=GOOGLE_API_KEY)

# 2. Setup Groq (Brain)
groq_client = Groq(api_key=GROQ_API_KEY)

app = FastAPI()

# --- DATABASE SETUP ---
client = AsyncIOMotorClient(MONGO_URL, tlsCAFile=certifi.where())
db = client.math_solver_db 
history_collection = db.history 

# --- DATA MODELS ---
class MathRequest(BaseModel):
    equation: str

class HistoryItem(BaseModel):
    user_id: str
    equation: str
    solution: str = None
    explanation: str = None
    timestamp: str = None
    hint_chat: list = []
    tutor_chat: list = []
    mode_used: str = "solve"
    topic: str = None 

class ChatRequest(BaseModel):
    context: str
    history: list
    message: str
    mode: str = "tutor"
    user_id: str | None = None 

class ChatUpdate(BaseModel):
    chat_history: list
    mode: str

from bson import ObjectId

# --- ENDPOINTS ---

@app.get("/")
def read_root():
    return {"status": "Hybrid Server Running (Gemini Vision + Groq Brain)"}

# 1. VISION: GEMINI (Extract Text Only)
@app.post("/api/extract")
async def extract_from_image(file: UploadFile = File(...)):
    os.makedirs("uploads", exist_ok=True)
    file_path = f"uploads/{file.filename}"
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    try:
        # Use Flash for fast OCR
        model = genai.GenerativeModel('models/gemini-2.5-flash')
        img = Image.open(file_path)
        prompt = (
    "Extract the math problem from this image. "
    "Rules: "
    "1. Do NOT use LaTeX delimiters like '$' or '\\(' or '\\['. "
    "2. Just write the math naturally (e.g. '2x + 5 = 10'). "
    "3. Preserve the exact text of word problems."
)
        response = model.generate_content([prompt, img])
        return {"equation": response.text.strip()}
    except Exception as e:
        return {"error": f"OCR Error: {str(e)}"}

# 2. SOLVER: GROQ (Llama 3 - 70b)
@app.post("/api/calculate")
async def calculate_solution(request: MathRequest):
    prompt = f"""
    Act as a math tutor. Solve this problem: "{request.equation}"
    
    Return a strictly valid JSON response with exactly these keys:
    {{
      "solution": "The final concise answer in LaTeX (no dollar signs)",
      "explanation": "A step-by-step explanation in LaTeX (use single dollar signs for math)"
    }}
    
    Do not add markdown formatting like ```json. Just the raw JSON string.
    """
    
    try:
        # Use Llama-3.3-70b (Very smart, very fast)
        completion = groq_client.chat.completions.create(
            messages=[{"role": "user", "content": prompt}],
            model="llama-3.3-70b-versatile",
            temperature=0,
            response_format={"type": "json_object"} # Force JSON mode
        )
        
        text = completion.choices[0].message.content
        data = json.loads(text)
        
        return {
            "solution": data.get("solution", "Error"),
            "explanation": data.get("explanation", "Explanation unavailable")
        }
        
    except Exception as e:
        return {
            "solution": r"\text{Error}",
            "explanation": f"Solver Error: {str(e)}"
        }

# 3. CHAT: GROQ (Llama 3 - 8b for speed or 70b for smarts)
@app.post("/api/chat")
async def chat_with_tutor(request: ChatRequest):
    try:
        # Convert Gemini history format to Groq format
        groq_history = []
        for msg in request.history:
            role = "assistant" if msg['role'] == "model" else "user"
            content = msg.get("parts", [{}])[0].get("text", "") if "parts" in msg else msg.get("text", "")
            if content:
                groq_history.append({"role": role, "content": content})
        mode = getattr(request, "mode", "tutor")
        # --- SELECT PROMPT BASED ON MODE ---
        if request.mode == "hint":
            # Mode A: Socratic Hint Giver (Strict)
            system_instruction = (
                f"You are a socractic math tutor. Context: {request.context}. "
                "Your Goal: Guide the user to the answer, do NOT give it to them.\n"
                "RULES:\n"
                "1. Never solve the problem completely.\n"
                "2. Provide only one logical step or formula at a time.\n"
                "3. Ask a guiding question to check their understanding.\n"
                "4. Use LaTeX format (wrap in $) for all math expressions.\n"
                "5. Keep responses concise (under 3 sentences)."
            )
        else:
            # Mode B: Helpful Tutor (Explains Doubts)
            system_instruction = (
                f"You are a helpful math tutor. Context: {request.context}. "
                "The user already has the solution but needs help understanding it.\n"
                "Your Goal: Clear their doubts and explain the concepts.\n"
                "RULES:\n"
                "1. Answer their specific question clearly and directly.\n"
                "2. You CAN explain the steps in detail.\n"
                "3. Use analogies if it helps.\n"
                "4. Use LaTeX format (wrap in $) for all math expressions.\n"
                "5. Be encouraging and patient."
            )

        system_msg = {"role": "system", "content": system_instruction}
        
        messages = [system_msg] + groq_history + [{"role": "user", "content": request.message}]
        
        completion = groq_client.chat.completions.create(
            messages=messages,
            model="llama-3.3-70b-versatile",
        )
        
        reply = completion.choices[0].message.content
        if not reply:
            return {"reply": "Sorry, I couldn't generate a response. Try again."}
        return {"reply": reply.replace("$$", "$")} 
        
    except Exception as e:
        return {"error": str(e)}

# 4. HISTORY ENDPOINTS (Unchanged)
@app.post("/api/history")
async def save_history(item: HistoryItem):
    try:
        item.timestamp = datetime.now(timezone.utc).isoformat()

        item.topic = classify_topic_with_groq(item.equation)

        # 🔧 ADD THIS
        if item.solution == "Hint Session":
            item.mode_used = "hint"
        else:
            item.mode_used = "solve"

        result = await history_collection.insert_one(item.dict())
        return {"message": "Saved", "id": str(result.inserted_id)}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    
@app.get("/api/history")
async def get_history(user_id:str):
    try:
        history_list = []
        cursor = history_collection.find({"user_id": user_id}).sort("_id", -1).limit(20)

        async for document in cursor:
            document["_id"] = str(document["_id"])
            history_list.append(document)
        return history_list
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/history/{id}")
async def get_history_item(id: str,user_id: str):
    try:
        doc = await history_collection.find_one({
    "_id": ObjectId(id),
    "user_id": user_id
})
        if doc:
            doc["_id"] = str(doc["_id"])
            return doc
        raise HTTPException(status_code=404, detail="Item not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/history/{id}")
async def update_history_chat(id: str, update: ChatUpdate, user_id: str):
    try:
        field = "hint_chat" if update.mode == "hint" else "tutor_chat"

        await history_collection.update_one(
            {
                "_id": ObjectId(id),
                "user_id": user_id
            },
            {"$set": {field: update.chat_history}}
        )

        return {"message": "Chat updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/history/{id}/chat")
async def clear_chat_history(id: str, user_id: str):
    try:
        await history_collection.update_one(
            {
                "_id": ObjectId(id),
                "user_id": user_id
            },
            {"$set": {"hint_chat": [], "tutor_chat": []}}
        )
        return {"message": "Chat cleared"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/dashboard/topics")
async def dashboard_topics(user_id: str):
    pipeline = [
        {
            "$match": {
                "user_id": user_id,
                "topic": {"$ne": None}
            }
        },
        {
            "$group": {
                "_id": "$topic",
                "count": {"$sum": 1}
            }
        },
        {"$sort": {"count": -1}}
    ]

    result = []
    async for doc in history_collection.aggregate(pipeline):
        result.append({
            "topic": doc["_id"],
            "count": doc["count"]
        })

    return result

# --- HELPER FUNCTIONS ---
# Ensure you have imports: 
# from sympy import sympify, solve, Symbol, Eq, parse_expr, latex
# from sympy.parsing.sympy_parser import standard_transformations, implicit_multiplication_application

def image_to_full_text(image_path):
    """
    OCR using Gemini 2.5 Flash.
    Optimized to preserve mathematical structure (LaTeX).
    """
    try:
        model = genai.GenerativeModel("models/gemini-2.5-flash")
        img = Image.open(image_path)

        prompt = (
            "You are a mathematical OCR engine. Extract all text and math from this image.\n"
            "Rules:\n"
            "1. Output valid LaTeX for all mathematical expressions (e.g., use \\frac{a}{b} not a/b).\n"
            "2. Preserve the exact text of word problems.\n"
            "3. Do not solve the problem. Just extract the text."
        )

        response = model.generate_content([prompt, img])

        if not response or not response.text:
            return ""

        return response.text.strip()

    except Exception as e:
        print(f"OCR ERROR: {e}")
        return ""


def solve_math_problem_with_groq(problem_text):
    """
    Solves the problem AND generates explanation in ONE call.
    Uses Llama-3.3-70b (Smartest Model) on Groq.
    """
    prompt = f"""
    Act as an expert math tutor. Solve this problem:
    
    PROBLEM:
    "{problem_text}"

    INSTRUCTIONS:
    1. Solve the problem step-by-step.
    2. Provide the final answer in LaTeX format.
    3. Return the result in strictly valid JSON format.

    JSON STRUCTURE:
    {{
      "solution": "Final Answer in LaTeX (e.g. x = 5)",
      "explanation": "Step-by-step explanation. Use **Step 1:** format. Use LaTeX for math."
    }}
    """

    try:
        completion = groq_client.chat.completions.create(
            model="llama-3.1-8b-instant", # Much smarter than 8b
            messages=[
                {"role": "system", "content": "You are a JSON-speaking math machine."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.1, # Low temp for precision
            response_format={"type": "json_object"} # Force valid JSON
        )
        
        # Parse the JSON response
        import json
        content = completion.choices[0].message.content
        data = json.loads(content)
        
        return data.get("solution"), data.get("explanation")

    except Exception as e:
        print(f"Groq Error: {e}")
        # Fallback if JSON fails
        return r"\text{Error}", "Could not solve this problem."


# --- OPTIONAL: SYMPY (Keep this only if you really want a non-AI check) ---
def sanitize_for_sympy(equation):
    equation = equation.replace("$", "").replace(r"\(", "").replace(r"\)", "")
    equation = equation.replace("^", "**").replace(r"\times", "*")
    return equation

def solve_with_sympy(equation_str):
    """
    Tries to solve simple algebra using Python's Symbolic Math library.
    Returns None if it gets too complicated (so AI takes over).
    """
    try:
        # 1. Clean up string
        equation_str = sanitize_for_sympy(equation_str)
        
        # 2. Check for '='
        if "=" not in equation_str: 
            return None # Not an equation we can solve directly
            
        parts = equation_str.split("=")
        if len(parts) != 2: return None
        
        # 3. Setup SymPy
        x = Symbol("x")
        transformations = standard_transformations + (implicit_multiplication_application,)
        
        lhs = parse_expr(parts[0], transformations=transformations)
        rhs = parse_expr(parts[1], transformations=transformations)
        
        # 4. Solve
        eq = Eq(lhs, rhs)
        result = solve(eq, x)
        
        if not result: return None
        
        return latex(result)
        
    except Exception:
        return None

def generate_explanation(equation, solution):
    """
    Generates an explanation for a KNOWN solution (found by SymPy).
    """
    prompt = f"""
    You are a math tutor. I have already solved this problem.
    
    PROBLEM: {equation}
    KNOWN ANSWER: {solution}
    
    TASK:
    Explain how to get from the problem to the answer step-by-step.
    
    RULES:
    1. Use **Step 1:**, **Step 2:** format.
    2. Use LaTeX for all math expressions (wrapped in single $).
    3. Be concise but clear.
    """

    try:
        completion = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system", "content": "You are a helpful math tutor."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3, 
        )
        
        return completion.choices[0].message.content.strip()

    except Exception as e:
        print(f"Explanation Error: {e}")
        return "Explanation unavailable."

def classify_topic_with_groq(problem_text: str) -> str:
    prompt = f"""
    You are classifying a math / signals problem into a
    SINGLE, CHAPTER-LEVEL topic (not broad domains).

    Follow these rules strictly:
    1. Output ONLY the topic name.
    2. Topic must be specific and syllabus-level.
    3. Do NOT use generic labels like "Math", "Calculus", "Signals".
    4. Capitalize Properly.

    Examples of GOOD topics:
    - Indefinite Integration
    - Definite Integration
    - Applications of Integrals
    - First Order Differential Equations
    - Second Order Differential Equations
    - Continuous-Time Fourier Transform
    - Discrete-Time Fourier Transform
    - Properties of Fourier Transform
    - Convolution in Time Domain
    - Laplace Transform
    - Inverse Laplace Transform
    - Z-Transform
    - Discrete-Time Signals
    - Continuous-Time Signals

    Problem:
    {problem_text}

    Respond with ONLY one topic name.
    """

    try:
        completion = groq_client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": prompt}],
            temperature=0,
        )
        return completion.choices[0].message.content.strip()
    except Exception:
        return "General"
