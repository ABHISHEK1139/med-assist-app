# Med Assist App — Local Medical AI Assistant 🩺

A privacy-first, local medical AI application built for PC-to-phone portability. Run a medical AI on your PC's GPU and connect securely from your Android phone over local WiFi. 

Recently upgraded with the **Ultimate Master Upgrade Plan**, Med Assist App is now a flagship-level health companion!

## 🎯 Overview & New Flagship Features

Med Assist App is powered by **Gemma-2-2B** (local GPU) OR **Any Cloud Provider** (OpenAI, Gemini, Anthropic, etc.). You have full control — run entirely on your own hardware for maximum privacy, or connect to powerful cloud models.

### ✨ The "WOW Factor" Experience
- 🎨 **Glassmorphism UI** — Stunning frosted glass app bars, message bubbles, and radial menus for a premium feel.
- 🎙️ **Voice Input & Accessibility** — Tap the microphone icon for quick Speech-to-Text entry on the fly.
- 🌊 **Fluid Animations** — Everything slides, fades, and pulses naturally using `flutter_animate`.

### 🧠 Radical AI Features
- 🏛️ **Multi-Agent Consultation Room** — Toggle "Consultation Mode" (🧠) to trigger a 3-agent debate. The AI spins up a **Diagnostician**, **Clinical Pharmacist**, and **Lead Physician** to evaluate your complex queries and synthesize a final answer.
- 💊 **Pill Bottle OCR** — Tap the `+` menu and select "Pill OCR". Take a picture of any pill bottle, and the app uses local Machine Learning to instantly extract the drug name and dosage directly into your chat.
- ⌚ **Wearable Health Sync** — Connects to Apple Health / Google Fit to automatically pull daily steps, heart rate, and sleep data into the AI's context window.
- 🔬 **Live Medical Database Integration** — If you ask about drug recalls or complex literature, the AI can autonomously decide to query **OpenFDA** and **PubMed** in real-time, retrieving live citations instead of relying solely on offline weights.
- 🚑 **Emergency Caregiver Export** — With one tap in the Digital Health Archive, instantly generate and share a clean, printable PDF summarizing your active conditions, allergies, and medications.

### Core Capabilities
- 🔒 **100% Local Configurable** — Keep your data off the cloud by running locally, or plug in an API key via `litellm`.
- 📄 **Document Memory (RAG)** — Upload PDFs, lab reports, and images. ChromaDB retrieves relevant context for each query.
- 🏥 **Digital Health Archive** — Automatically extracts conditions, medications, allergies, and surgeries from conversations.
- 📱 **Phone-to-PC Architecture** — Phone stores your sensitive health data; PC runs the heavy model computation.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Frontend (Phone)                  │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │ Chat UI  │  │ Radial Menus │  │  PDF Export Service   │  │
│  │ (BLoC)   │  │ & OCR Vision │  │  (Caregiver Profile)  │  │
│  └────┬─────┘  └──────┬───────┘  └───────────┬───────────┘  │
│       │               │                      │              │
│  ┌────┴───────────────┴──────────────────────┴───────────┐  │
│  │ Health Archive (SQLite) & Wearable Sync (Health API)  │  │
│  └───────────────────────┬───────────────────────────────┘  │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTP/REST (Local WiFi)
┌──────────────────────────▼──────────────────────────────────┐
│                    Python Backend (PC)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  FastAPI    │  │ LiteLLM (Any)│  │    ChromaDB      │   │
│  │  Server     │◄─┤ OR Gemma GPU │◄─┤  Vector Store    │   │
│  └──────┬──────┘  └──────────────┘  └──────────────────┘   │
│         │                                                   │
│  ┌──────┴──────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Multi-Agent │  │  Live APIs   │  │   Telegram       │   │
│  │ Engine      │  │(FDA/PubMed)  │  │   Bot Bridge     │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites
| Requirement | Version | Notes |
|---|---|---|
| **Python** | 3.10+ | Backend server |
| **Flutter** | 3.16+ | Frontend app |
| **CUDA GPU** | 4GB+ VRAM | RTX 3050 or better recommended |
| **RAM** | 8GB+ | 16GB recommended |

### Step 1: Setup & Run the Backend
```bash
git clone <your-repo-url>
cd "med ai/backend"

# Create and activate virtual environment
python -m venv venv
.\venv\Scripts\activate # Windows

# Install dependencies
pip install -r requirements.txt

# Copy environment config & add token if needed
copy .env.example .env

# Start the server (allow remote connections)
python -m uvicorn src.api.server:app --reload --host 0.0.0.0 --port 8000
```
> The server will expose the new `/chat/consultation` endpoints for the Multi-Agent engine!

### Step 2: Setup & Run the Frontend
Because this app now uses local ML OCR and Health packages, running on a physical device is highly recommended.

```bash
cd "../frontend"

# Get Flutter dependencies
flutter pub get

# Run on Android (phone connected via USB)
flutter run
```

### Step 3: Connect Phone to PC
1. Ensure both devices are on the **same WiFi network**.
2. Open the app on your phone → Go to **PC Connection** screen.
3. Enter your PC's local IP address (e.g., `192.168.1.100`) and port `8000`.

## ⚙️ Configuration
All settings are managed via environment variables or `.env` file. See [.env.example](.env.example) for all options:

| Variable | Default | Description |
|---|---|---|
| `MED_ASSIST_APP_HOST` | `127.0.0.1` | Server bind address |
| `MED_ASSIST_APP_USE_GPU` | `true` | Enable GPU acceleration |
| `MED_ASSIST_APP_MEMORY_RETENTION_DAYS` | `30` | Document retention period |

## 🧪 GitHub Actions CI
This project includes a CI workflow (`.github/workflows/ci.yml`) that checks Python syntax and runs `flutter analyze` for static analysis.

## 📄 License
This project is licensed under the **MIT License** — see [LICENSE](LICENSE).

## ⚠️ Medical Disclaimer
**Med Assist App is a development prototype and is NOT intended for actual medical use.**
- All AI outputs are informational only and may be inaccurate.
- Never use this application as a substitute for professional medical advice.
- Always consult qualified healthcare professionals for medical decisions.
- The developers assume no liability for any actions taken based on AI outputs.
