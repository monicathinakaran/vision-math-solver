from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel
import shutil
import os
from PIL import Image
from sympy import sympify, solve, Symbol, Eq, parse_expr, latex
from sympy.parsing.sympy_parser import standard_transformations, implicit_multiplication_application
from groq import Groq
from pathlib import Path # <--- Import Path
import certifi
from bson import ObjectId
import easyocr
import cv2
import numpy as np

# --- DB IMPORTS ---
from motor.motor_asyncio import AsyncIOMotorClient
from datetime import datetime
from dotenv import load_dotenv # Make sure you have python-dotenv installed

# 1. Explicitly find the path to the .env file in the current folder
env_path = Path(__file__).parent / ".env"

# 2. Load that specific file
load_dotenv(dotenv_path=env_path)

# 3. Now get the key
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
MONGO_URL = os.getenv("MONGO_URL")
groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))

if not GROQ_API_KEY:
    raise ValueError(f"No API key found. Please ensure '{env_path}' exists and contains GROQ_API_KEY.")

import google.generativeai as genai
genai.configure(api_key=GROQ_API_KEY)

genai.configure(api_key=GROQ_API_KEY)
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
        raw_text = image_to_full_text(file_path)

        if raw_text:
            cleaned = clean_ocr_text_with_ai(raw_text)
        else:
            cleaned = ""

        return {"equation": cleaned}
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
    completion = groq_client.chat.completions.create(
        model="llama3-8b-8192",
        messages=[
            {"role": "system", "content": "You are a helpful math tutor."},
            *request.history,
            {"role": "user", "content": request.message}
        ],
        temperature=0.6
    )

    return {"reply": completion.choices[0].message.content}

    
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
# 7. CLEAR CHAT HISTORY
@app.delete("/api/history/{id}/chat")
async def clear_chat_history(id: str):
    try:
        result = await history_collection.update_one(
            {"_id": ObjectId(id)},
            {"$set": {"chat_history": []}} # Empty the list
        )
        return {"message": "Chat cleared"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 8. GET SINGLE HISTORY ITEM (For Persistence)
@app.get("/api/history/{id}")
async def get_history_item(id: str):
    try:
        doc = await history_collection.find_one({"_id": ObjectId(id)})
        if doc:
            doc["_id"] = str(doc["_id"])
            return doc
        raise HTTPException(status_code=404, detail="Item not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
     
# --- HELPER FUNCTIONS ---
ocr_reader = easyocr.Reader(['en'], gpu=False)

def image_to_full_text(image_path):
    """
    Extracts ALL text from image using EasyOCR.
    Works for equations + word problems.
    No AI, no quota, fully free.
    """
    # Read image
    image = cv2.imread(image_path)
    if image is None:
        return ""

    # Convert to grayscale
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    # Slight thresholding improves math OCR
    gray = cv2.adaptiveThreshold(
        gray, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        11, 2
    )

    # OCR
    results = ocr_reader.readtext(gray, detail=0)

    # Join lines into one problem statement
    extracted_text = " ".join(results)

    return extracted_text.strip()

def clean_ocr_text_with_ai(raw_text):
    completion = groq_client.chat.completions.create(
        model="llama3-8b-8192",
        messages=[
            {
                "role": "system",
                "content": (
                    "You clean OCR math text.\n"
                    "Return only the cleaned math problem.\n"
                    "Remove noise. Preserve meaning."
                )
            },
            {
                "role": "user",
                "content": raw_text
            }
        ],
        temperature=0.0
    )
    return completion.choices[0].message.content.strip()

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
    completion = groq_client.chat.completions.create(
        model="llama3-8b-8192",
        messages=[
            {
                "role": "system",
                "content": "You are a math solver. Return ONLY the final answer in LaTeX. No explanations."
            },
            {
                "role": "user",
                "content": problem_text
            }
        ],
        temperature=0.2
    )

    return completion.choices[0].message.content.strip()

def generate_explanation(equation, solution):
    completion = groq_client.chat.completions.create(
        model="llama3-8b-8192",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a math tutor. Explain step by step.\n"
                    "Rules:\n"
                    "1. Use paragraphs, no bullet points\n"
                    "2. Use **Step X:** format\n"
                    "3. Use LaTeX with single $"
                )
            },
            {
                "role": "user",
                "content": f"Problem: {equation}\nSolution: {solution}"
            }
        ],
        temperature=0.4
    )

    return completion.choices[0].message.content.strip()
