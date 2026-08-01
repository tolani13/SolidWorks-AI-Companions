# SolidWorks AI Companions

Three private, transferable engineering companions:

- **ORBIT** — context, documentation, learning, and grounded answers.
- **FORGE** — controlled SOLIDWORKS inspection and automation.
- **PRISM** — materials, science, validation, and evidence review.

This bundle is independent software. It does not copy Dassault Systèmes source
code, models, branding, or proprietary SOLIDWORKS AI services.

## What is included

- A dependency-free Python/Tkinter sidecar interface.
- Installable Codex skills for all three companions.
- A whitelisted PowerShell bridge to a running SOLIDWORKS desktop session.
- Local Ollama and generic OpenAI-compatible provider support.
- A clipboard mode that works with Codex, Claude, or another chat without an
  API key.
- Transfer, installation, testing, and packaging scripts.

The application never executes arbitrary model-generated shell commands.
FORGE may propose only actions from the bridge allowlist, and every modifying
action requires explicit approval in the sidecar.

## Start on this computer

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Start.ps1
```

The first run creates a user configuration under:

```text
%LOCALAPPDATA%\SolidWorksAICompanions\config.json
```

### Provider modes

- `clipboard` requires no model service. Send copies a grounded prompt to the
  clipboard; paste it into Codex or Claude, copy the response, and click
  **Import response**.
- `ollama` calls a locally running Ollama service. Set the model name in the
  sidecar.
- `openai_compatible` calls a `/v1/chat/completions` endpoint. Store its key in
  the environment variable named by `api_key_env`; never put a secret in the
  configuration file.

## Connect to SOLIDWORKS

Start SOLIDWORKS and open a part, assembly, or drawing. In the sidecar, choose
FORGE and click **Inspect model**.

The bridge currently supports:

- Read connection and active-document status.
- Inspect the active document, configuration, features, feature errors,
  document custom properties, and assembly component summaries.
- Rebuild and force rebuild.
- Save the active document.
- Export the active document to STEP or PDF.
- Add or replace a document-level text custom property.

Exports refuse to overwrite an existing file unless the approved action
explicitly includes `"overwrite": true`.

SOLIDWORKS Connected supports most standard macros and APIs, but its platform
file-management behavior differs from traditional desktop SOLIDWORKS. Maker
files remain Maker-watermarked regardless of this bridge.

## Install the Codex skills

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -InstallCodexSkills
```

Restart Codex after installation. The skills are:

- `$solidworks-orbit`
- `$solidworks-forge`
- `$solidworks-prism`

## Transfer to the desktop

Create a clean archive:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Package.ps1
```

Copy the resulting ZIP from `dist` to the desktop, extract it, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -InstallCodexSkills -CreateDesktopShortcut
```

The archive excludes configuration, chat data, logs, API keys, and caches.
The adjacent `.sha256` file lets you verify that the ZIP copied intact:

```powershell
(Get-FileHash .\SolidWorks-AI-Companions-portable.zip -Algorithm SHA256).Hash
```

## Validate

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

The test suite validates Python modules, prompt/action parsing, skill structure,
and safe bridge failure when SOLIDWORKS is not running. Live CAD mutations are
intentionally not performed by automated tests.
