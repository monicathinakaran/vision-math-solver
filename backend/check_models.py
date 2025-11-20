# backend/check_models.py
import google.generativeai as genai

# --- PASTE YOUR KEY HERE ---
GOOGLE_API_KEY = "AIzaSyBt7c5tTjl4iEIMa73dU_1OjQedjKHLJjQ"
genai.configure(api_key=GOOGLE_API_KEY)

print("Checking available models for your API key...\n")

try:
    count = 0
    for m in genai.list_models():
        # We only care about models that can generate text/chat
        if 'generateContent' in m.supported_generation_methods:
            print(f"Model Name: {m.name}")
            print(f"Display Name: {m.display_name}")
            print("-" * 30)
            count += 1
    print(f"\nTotal models found: {count}")

except Exception as e:
    print(f"Error: {e}")