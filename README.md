# Med Assist App — Local Medical AI Assistant

A privacy-first, local medical AI application built for PC-to-phone portability. Run a medical AI on your PC's GPU and connect securely from your Android phone over local WiFi.

## 🎯 Overview

    Med Assist App is a hybrid medical AI assistant powered by **Gemma-2-2B** (local GPU) OR **Any Cloud Provider** (OpenAI, Gemini, Anthropic, etc.). You have full control — run entirely on your own hardware for maximum privacy, or connect to powerful cloud models.

    ### Key Features

    - 🔒 **100% Local or Cloud Configurable** — You choose. Run Gemma 2B locally (no data leaves your device), or plug in an API key for GPT-4 / Claude / Gemini.
    - 🌍 **Multi-Provider Support** — Integrated with `litellm` to support 100+ AI models via a single `.env` variable (`MED_ASSIST_APP_AI_MODEL`).
- 🧠 **Agentic AI Reasoning** — Multi-step reasoning with tool calls (symptom queries, health data lookups).
- 📄 **Document Memory (RAG)** — Upload PDFs, lab reports, and images. ChromaDB retrieves relevant context for each query.
- 💡 **Explainability** — See which documents influenced each AI response ("Why?" button).
- 📱 **Phone-to-PC Architecture** — Phone stores health data; PC runs the model on GPU.
- 🤖 **Telegram Bot Bridge** — Optional Telegram integration for chat access.
- 🏥 **Digital Health Archive** — Automatically extracts conditions, medications, allergies, and surgeries from conversations.
- 📸 **Medical Image Analysis** — OCR and image processing for prescriptions, lab reports, X-rays.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Frontend (Phone)                  │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │ Chat UI  │  │Privacy Badge │  │ Explainability Drawer │  │
│  │ (BLoC)   │  │(local badge) │  │ (document citations)  │  │
│  └────┬─────┘  └──────────────┘  └───────────────────────┘  │
│       │                                                     │
│  ┌────┴──────────────────────────────────────────────────┐  │
│  │ Health Archive (SQLite + Hive) — stored on PHONE      │  │
│  │ Symptoms · Conditions · Medications · Allergies       │  │
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
│  │  Agentic    │  │   Profile    │  │   Telegram       │   │
│  │  Engine     │  │   Manager    │  │   Bot Bridge     │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 📂 Project Structure

```
med ai/
├── backend/                          # Python Backend
│   ├── main.py                       # Entry point (uvicorn server)
│   ├── requirements.txt              # Python dependencies
│   ├── models/                       # Model files (.task) — gitignored
│   ├── memory/                       # ChromaDB vector store — gitignored
│   ├── logs/                         # Server logs — gitignored
│   └── src/
│       ├── config.py                 # Settings (pydantic-settings, .env)
│       ├── api/
│       │   ├── server.py             # FastAPI app, lifespan, CORS
│       │   └── routes.py             # All REST endpoints
│       ├── inference/
│       │   ├── llm_service.py        # HuggingFace Transformers + MockLLM
│       │   ├── agentic_engine.py     # ReAct-style multi-step reasoning
│       │   ├── image_processor.py    # OCR + image analysis
│       │   └── prompt_templates.py   # Medical prompt engineering + RAG
│       ├── memory/
│       │   ├── vector_store.py       # ChromaDB vector search
│       │   └── document_processor.py # PDF, image, text processing
│       ├── profile/
│       │   └── profile_manager.py    # Health archive + entity extraction
│       └── telegram/
│           └── bot.py                # Telegram bot bridge
│
├── frontend/                         # Flutter/Dart Frontend
│   ├── pubspec.yaml                  # Flutter dependencies
│   ├── analysis_options.yaml         # Linter rules
│   ├── android/                      # Android build config
│   ├── assets/                       # Fonts, icons, images, models
│   └── lib/
│       ├── main.dart                 # App entry point
│       ├── core/
│       │   ├── constants/            # API config, UI constants
│       │   └── theme/                # Dark theme, glassmorphism
│       ├── features/
│       │   ├── chat/                 # Chat BLoC, UI, message bubbles
│       │   ├── explainability/       # "Why?" document citation drawer
│       │   ├── history/              # Chat history with search
│       │   └── profile/              # Health archive UI
│       ├── screens/                  # Documents, Health Archive, Model Init, PC Connection
│       ├── services/                 # AI, PC Backend, Health Archive, Model Manager
│       └── widgets/                  # AI Memory Widget, Privacy Badge
│
├── .env.example                      # Environment config template
├── .gitignore                        # Git ignore rules
├── LICENSE                           # MIT License
└── README.md                         # This file
```

## 🚀 Quick Start

### Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| **Python** | 3.10+ | Backend server |
| **Flutter** | 3.16+ | Frontend app |
| **CUDA GPU** | 4GB+ VRAM | RTX 3050 or better recommended |
| **RAM** | 8GB+ | 16GB recommended |
| **Hugging Face Account** | — | For downloading Gemma model (free) |

### Step 1: Clone the Repository

```bash
git clone <your-repo-url>
cd "med ai"
```

### Step 2: Setup & Run the Backend

```bash
cd backend

# Create and activate virtual environment
python -m venv venv
# Windows:
.\venv\Scripts\activate
# Linux/Mac:
# source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy environment config
copy .env.example .env
# Edit .env and add your Hugging Face token:
#   MED_ASSIST_APP_HF_TOKEN=hf_your_token_here

# Start the server
python main.py --debug
```

The server starts at `http://127.0.0.1:8000`. On first run, it downloads Gemma-2-2B (~1.5GB) from Hugging Face. If the model fails to load, the server automatically falls back to a **MockLLMService** so you can develop the frontend.

> **Tip**: To allow connections from your phone, use `--host 0.0.0.0`:
> ```bash
> python main.py --host 0.0.0.0 --port 8000 --debug
> ```

### Step 3: Setup & Run the Frontend

```bash
cd frontend

# Get Flutter dependencies
flutter pub get

# Run on Windows desktop
flutter run -d windows

# Run on Android (phone connected via USB)
flutter run -d <device-id>

# Build Android APK
flutter build apk --debug
```

### Step 4: Connect Phone to PC

1. Ensure both devices are on the **same WiFi network** (or use phone hotspot).
2. Open the app on your phone → Go to **PC Connection** screen.
3. Enter your PC's local IP address (e.g., `192.168.1.100`) and port `8000`.
4. Tap **Connect** — the app tests the connection automatically.

> **Firewall**: Make sure Windows Firewall allows inbound connections on port `8000`.

## 📡 API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/chat` | Send a message, get AI response |
| `POST` | `/chat/agentic` | Agentic chat with tool calls & multi-step reasoning |
| `POST` | `/chat/session/clear` | Clear server-side conversation memory |
| `GET`  | `/chat/session/info` | Get session info (debug) |
| `POST` | `/explain` | Explain how AI reached its conclusion ("Why?" button) |
| `GET`  | `/profile` | Get digital health archive |
| `POST` | `/profile` | Update health archive |
| `POST` | `/upload` | Upload a medical document (PDF, image, text) |
| `POST` | `/context` | Search stored documents for relevant context |
| `GET`  | `/documents` | List all stored documents |
| `GET`  | `/health` | System health check (model, GPU, memory status) |
| `POST` | `/memory/cleanup` | Remove old documents past retention period |

When `--debug` is enabled, interactive API docs are available at `/docs` (Swagger UI).

## ⚙️ Configuration

All settings are managed via environment variables or `.env` file. See [.env.example](.env.example) for all options:

| Variable | Default | Description |
|---|---|---|
| `MED_ASSIST_APP_HOST` | `127.0.0.1` | Server bind address |
| `MED_ASSIST_APP_PORT` | `8000` | Server port |
| `MED_ASSIST_APP_HF_TOKEN` | — | Hugging Face token (for Gemma download) |
| `MED_ASSIST_APP_MAX_TOKENS` | `1024` | Max response tokens |
| `MED_ASSIST_APP_TEMPERATURE` | `0.7` | Model temperature |
| `MED_ASSIST_APP_USE_GPU` | `true` | Enable GPU acceleration |
| `MED_ASSIST_APP_EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | Sentence embedding model |
| `MED_ASSIST_APP_MEMORY_RETENTION_DAYS` | `30` | Document retention period |
| `MED_ASSIST_APP_TELEGRAM_BOT_TOKEN` | — | Optional Telegram bot token |

## 🔧 Troubleshooting

| Problem | Solution |
|---|---|
| `CUDA out of memory` | Close other GPU apps. Gemma-2B with 4-bit quantization needs ~2GB VRAM. |
| `Model download fails` | Check `MED_ASSIST_APP_HF_TOKEN` in `.env`. Accept the Gemma license on Hugging Face. |
| `Phone can't connect` | Verify both devices on same network. Check Windows Firewall port 8000. Use `--host 0.0.0.0`. |
| `MockLLMService active` | Normal if PyTorch/CUDA not installed. Install torch: `pip install torch` |
| `flutter pub get fails` | Run `flutter doctor` and resolve issues. Ensure Dart SDK ≥3.2.0. |

## 🧪 GitHub Actions CI

This project includes a CI workflow (`.github/workflows/ci.yml`) that:

1. **Backend**: Checks Python syntax, validates imports
2. **Frontend**: Runs `flutter analyze` for static analysis

See the [CI workflow file](.github/workflows/ci.yml) for details.

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).

## ⚠️ Medical Disclaimer

**Med Assist App is a development prototype and is NOT intended for actual medical use.**

- All AI outputs are informational only and may be inaccurate.
- Never use this application as a substitute for professional medical advice.
- Always consult qualified healthcare professionals for medical decisions.
- The developers assume no liability for any actions taken based on AI outputs.
