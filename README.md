# Local MLX

A native macOS and iOS chat application for running large language models locally on Apple Silicon using [MLX](https://github.com/ml-explore/mlx), with support for OpenAI-compatible server backends.

Built with SwiftUI and SwiftData. Designed to be fast, private, and offline-capable.

## Features

### On-Device Inference
- Run LLMs directly on Apple Silicon via the [MLX Swift](https://github.com/ml-explore/mlx-swift) framework
- Download models from Hugging Face (e.g., `mlx-community/Qwen3-4B-4bit`)
- Real-time download progress tracking and model lifecycle management
- Zero network dependency once a model is downloaded

### Server Mode
- Connect to any OpenAI-compatible API endpoint (MLX server, Ollama, LM Studio, vLLM, etc.)
- Server-Sent Events (SSE) streaming for real-time token generation
- Connection health checks and model discovery via `/v1/models`
- Seamless switching between local and server inference

### Chat Interface
- Streaming responses with live token rendering and animated cursor
- Thinking/reasoning block support (`<think>` tags) with expandable, live-updating display during generation
- Code block rendering with language labels and one-tap copy
- Markdown rendering (bold, italic, inline code)
- Message regeneration and individual message deletion
- Context menus for copy, regenerate, and delete actions
- Auto-scroll with smart "near bottom" detection
- LLM-generated conversation starters on the welcome and empty chat screens

### Conversation Management
- Persistent conversation history stored locally via SwiftData
- Search conversations by title
- Time-grouped sidebar (Today, Yesterday, Previous 7 Days, Previous 30 Days, Older)
- Swipe-to-archive (left swipe, blue) and swipe-to-delete (right swipe, red)
- Collapsible archived conversations section
- Rename conversations via context menu or alert dialog
- Last message preview shows user's inquiry (not raw assistant output)

### Model Management
- Save and manage multiple model IDs for both local and server modes
- Quick model switching via interactive chip in the chat input area
- Auto-save current model to saved list on settings save
- Per-mode model lists with add/remove controls in settings

### Layout
- NavigationSplitView with sidebar and detail pane
- New chat button positioned next to sidebar toggle (ChatGPT-style)
- Home button in chat toolbar to return to welcome screen
- Settings accessible from sidebar bottom
- iOS splash screen with animated branding
- Responsive design adapting to macOS windows and iOS devices

## Architecture

```
Local-MLX/
├── Local_MLXApp.swift              # App entry point, SwiftData container
├── Models/
│   ├── ChatMessage.swift           # Message model (role, content, timestamp)
│   ├── Conversation.swift          # Conversation model with archive support
│   └── ServerConfig.swift          # Server/local config with saved model lists
├── ViewModels/
│   ├── ChatViewModel.swift         # Generation, streaming, think block parsing
│   └── ConversationListViewModel.swift  # CRUD + archive/unarchive
├── Views/
│   ├── MainView.swift              # NavigationSplitView, WelcomeView, ModelStatusChip
│   ├── ChatView.swift              # Message list, input, scroll management
│   ├── ConversationListView.swift  # Sidebar with grouped conversations
│   ├── MessageBubbleView.swift     # Message rendering, ThinkBlockView
│   ├── MessageInputView.swift      # Text input, model chips, send/stop
│   ├── EmptyChatView.swift         # Suggestion grid for new conversations
│   ├── CodeBlockView.swift         # Code display, ThinkParser, ContentParser
│   ├── SettingsView.swift          # Inference mode, server, model, prompt config
│   ├── ModelPickerView.swift       # Server model selection dropdown
│   ├── ModelDownloadView.swift     # Download progress and model lifecycle UI
│   └── SplashScreenView.swift      # iOS launch animation
└── Services/
    ├── MLXServerClient.swift       # OpenAI-compatible HTTP client (streaming + non-streaming)
    ├── LocalMLXClient.swift        # MLX Swift on-device inference
    ├── ModelManager.swift          # Model download, load, unload lifecycle
    ├── StreamingParser.swift       # SSE line parsing for chat completions
    └── HapticManager.swift         # Cross-platform haptic feedback
```

### Key Design Decisions

- **SwiftData** for persistence over Core Data — modern, declarative, and well-integrated with SwiftUI
- **@Observable** pattern (Observation framework) for ViewModels instead of Combine
- **AsyncThrowingStream** for both server and local inference streaming
- **Dual-mode architecture**: same ViewModel drives both local MLX and remote server generation
- **Cross-platform**: single codebase for macOS and iOS with `#if os()` conditionals where needed

## Requirements

- macOS 26.0+ / iOS 26.0+
- Xcode 17.0+
- Apple Silicon (M1 or later) for local inference
- Swift 6.0+

## Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/Local-MLX.git
   cd Local-MLX
   ```

2. **Open in Xcode**
   ```bash
   open Local-MLX.xcodeproj
   ```

3. **Resolve Swift packages** — Xcode will automatically fetch MLX, MLXLLM, and MLXLMCommon dependencies

4. **Select a target** — choose the macOS or iOS scheme

5. **Build and run** (`Cmd+R`)

### Local Mode Setup
1. Open Settings (gear icon at sidebar bottom)
2. Switch to "On-Device" mode
3. Enter a model ID (e.g., `mlx-community/Qwen3-4B-4bit`)
4. Tap "Download" and wait for completion
5. The model loads automatically — start chatting

### Server Mode Setup
1. Start an OpenAI-compatible server (e.g., `mlx_lm.server --model mlx-community/Qwen3-4B-4bit`)
2. Open Settings
3. Keep "Server" mode selected
4. Enter the server URL (default: `http://localhost:8080`)
5. Tap "Check Connection" to verify
6. Select a model from the picker

## Acknowledgements

This project is built on the work of the Apple MLX team and the open-source MLX ecosystem:

- **[MLX](https://github.com/ml-explore/mlx)** — Apple's array framework for machine learning on Apple Silicon
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Swift bindings for the MLX framework
- **[MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)** — Reference implementations for running LLMs with MLX in Swift
- **[MLX Community](https://huggingface.co/mlx-community)** — Hugging Face community providing quantized MLX-compatible model weights
- **[MLX LM](https://github.com/ml-explore/mlx-examples/tree/main/llms/mlx_lm)** — Python package for running and serving LLMs with MLX

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
