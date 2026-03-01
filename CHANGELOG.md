# Changelog

All notable changes to this project are documented here.

---

## v0.3.0 — UX Overhaul (2026-03-01)

Major interface redesign bringing the app closer to modern chat conventions. Nine features implemented across all view layers.

### Added
- **Home button in chat toolbar** — house icon in the navigation bar returns to the welcome screen without closing the conversation
- **Think block interaction during streaming** — thinking/reasoning blocks are now expandable while the model is still generating, with a live-updating chevron indicator
- **Swipe actions on conversations** — swipe right to delete (red, destructive), swipe left to archive (blue); replaces the old swipe-to-delete behavior
- **Conversation archiving** — `isArchived` flag on conversations, collapsible "Archived" section at the bottom of the sidebar, context menu archive/unarchive, and dedicated unarchive swipe action
- **Saved model lists** — `savedLocalModelIDs` and `savedServerModels` arrays persisted in `ServerConfig`, with add/remove UI in Settings and auto-append on save
- **Model switching via chip** — tapping the model status chip in the chat input opens a menu to switch between saved models; local mode triggers unload/reload, server mode uses the existing picker
- **LLM-generated suggestions** — welcome screen and empty chat screen request dynamic conversation starters from the active model, with hardcoded fallbacks on failure or timeout
- **Non-streaming chat endpoint** — `MLXServerClient.chat()` method for single-shot completions (used by the suggestion generator)
- **New chat button repositioned** — moved from the sidebar toolbar to the NavigationSplitView toolbar, appearing next to the sidebar toggle on iOS and in the navigation area on macOS
- **Settings relocated** — gear icon moved from the top toolbar to a "Settings" button at the bottom of the sidebar via `safeAreaInset`

### Fixed
- **Sidebar preview showing `<think>` tags** — `lastMessagePreview` now displays the last user message instead of raw assistant content containing think blocks

### Changed
- `ConversationListView` now accepts `onSettingsTap` callback instead of managing its own settings toolbar item
- `ChatView` accepts `onGoHome` and `onLocalModelChange` callbacks threaded from `MainView`
- `MessageInputView` consolidates model chips: shows `LocalModelSwitchChip` in local mode, `modelPickerChip` in server mode with available models, or a static `ModelStatusChip` as fallback
- `ConversationListViewModel` gains `archiveConversation(_:)` and `unarchiveConversation(_:)` methods
- Filtered conversation list excludes archived items from the main time-grouped sections

---

## v0.2.0 — Full Chat Interface (2026-02-27)

Complete chat application with MVVM architecture, streaming inference, and conversation management.

### Added
- **SwiftData persistence** — `Conversation`, `ChatMessage`, and `ServerConfig` models with cascade delete relationships
- **MVVM architecture** — `ChatViewModel` for generation state and `ConversationListViewModel` for conversation CRUD
- **Server streaming** — `MLXServerClient` with SSE parsing via `StreamingParser`, OpenAI-compatible `/v1/chat/completions` endpoint
- **Local inference** — `LocalMLXClient` bridging to MLX/MLXLLM for on-device token generation
- **Model management** — `ModelManager` handling download, cache checking, loading, and unloading of MLX models from Hugging Face
- **NavigationSplitView layout** — sidebar with conversation list, detail pane with chat or welcome view
- **Conversation list** — time-grouped sections (Today, Yesterday, Previous 7/30 Days, Older), search, rename, delete, context menus
- **Chat view** — `ScrollViewReader` with smart auto-scroll, streaming content display, error banners, message context menus
- **Message rendering** — `MessageRowView` with role-specific avatars, `ThinkBlockView` for reasoning display, `CodeBlockView` with language labels and copy buttons
- **Content parsing** — `ThinkParser` for `<think>` tag extraction, `ContentParser` for code fence detection via regex
- **Message input** — expanding text field, send/stop toggle with animated transitions, model picker chip for server mode
- **Settings** — inference mode picker (Server / On-Device), server URL with connection test, model picker from `/v1/models`, local model ID with download UI, system prompt editor
- **Model download UI** — `ModelDownloadView` with progress bar, state-driven action buttons, and file size estimates
- **Welcome screen** — branded landing with input field and four suggestion buttons
- **Haptic feedback** — `HapticManager` for light, medium, and success feedback on iOS
- **iOS splash screen** — animated icon and text with spring transitions
- **App Sandbox** — network entitlements for HTTP connections to local servers
- **ATS exceptions** — `NSAllowsLocalNetworking` for localhost server access

---

## v0.1.0 — Initial Scaffold (2026-02-27)

Bare Xcode project generated as the starting point.

### Added
- Xcode project with macOS and iOS targets
- Default `ContentView` with "Hello, world!" placeholder
- Asset catalog with accent color and app icon slots
- SwiftUI app entry point (`Local_MLXApp`)
