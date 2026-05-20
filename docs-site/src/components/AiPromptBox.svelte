<script lang="ts">
  const DOCS_URL = 'https://aadhii-yz.github.io/PocketLedger/llms-full.txt';

  const PLATFORMS = [
    { id: 'claude',     name: 'Claude',     url: 'https://claude.ai/new',                    param: 'q' },
    { id: 'chatgpt',   name: 'ChatGPT',    url: 'https://chatgpt.com/',                      param: 'q' },
    { id: 'gemini',    name: 'Gemini',     url: 'https://gemini.google.com/app',             param: 'q' },
    { id: 'perplexity',name: 'Perplexity', url: 'https://www.perplexity.ai/search',          param: 'q' },
  ] as const;

  let question = $state('');
  let platform = $state<typeof PLATFORMS[number]['id']>('claude');

  function submit() {
    const q = question.trim();
    if (!q) return;
    const p = PLATFORMS.find(x => x.id === platform)!;
    const full = `You are an expert assistant for PocketLedger, a multi-location inventory and billing system.\nFull documentation: ${DOCS_URL}\n\n${q}`;
    const url = new URL(p.url);
    url.searchParams.set(p.param, full);
    window.open(url.toString(), '_blank', 'noopener,noreferrer');
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) submit();
  }
</script>

<div class="ai-box">
  <div class="ai-box__header">
    <span class="ai-box__label">Ask AI about PocketLedger</span>
    <div class="ai-box__selector">
      {#each PLATFORMS as p}
        <button
          class="ai-box__chip"
          class:ai-box__chip--active={platform === p.id}
          onclick={() => (platform = p.id)}
          type="button"
        >{p.name}</button>
      {/each}
    </div>
  </div>

  <textarea
    class="ai-box__textarea"
    placeholder="Ask a question about installation, features, printing, or troubleshooting… (⌘↵ to send)"
    rows="3"
    bind:value={question}
    onkeydown={onKeydown}
  ></textarea>

  <div class="ai-box__footer">
    <span class="ai-box__hint">
      Context: the full docs will be included automatically.
    </span>
    <button class="ai-box__send" onclick={submit} disabled={!question.trim()} type="button">
      Ask {PLATFORMS.find(p => p.id === platform)?.name} →
    </button>
  </div>
</div>

<style>
  .ai-box {
    border: 1px solid var(--sl-color-gray-5);
    border-radius: 0.75rem;
    padding: 1rem 1.25rem;
    background: var(--sl-color-bg-sidebar);
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    margin-block: 2rem;
  }

  .ai-box__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.5rem;
  }

  .ai-box__label {
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--sl-color-gray-2);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .ai-box__selector {
    display: flex;
    gap: 0.25rem;
    flex-wrap: wrap;
  }

  .ai-box__chip {
    padding: 0.2rem 0.6rem;
    border-radius: 999px;
    font-size: 0.75rem;
    font-weight: 500;
    border: 1px solid var(--sl-color-gray-5);
    background: transparent;
    color: var(--sl-color-gray-2);
    cursor: pointer;
    transition: background 0.15s, color 0.15s, border-color 0.15s;
  }

  .ai-box__chip:hover {
    border-color: var(--sl-color-accent);
    color: var(--sl-color-accent);
  }

  .ai-box__chip--active {
    background: var(--sl-color-accent);
    border-color: var(--sl-color-accent);
    color: var(--sl-color-accent-high);
  }

  .ai-box__textarea {
    width: 100%;
    border: 1px solid var(--sl-color-gray-5);
    border-radius: 0.5rem;
    padding: 0.6rem 0.75rem;
    font-size: 0.875rem;
    background: var(--sl-color-bg);
    color: var(--sl-color-white);
    resize: vertical;
    font-family: inherit;
    line-height: 1.5;
    box-sizing: border-box;
    transition: border-color 0.15s;
  }

  .ai-box__textarea:focus {
    outline: none;
    border-color: var(--sl-color-accent);
  }

  .ai-box__footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .ai-box__hint {
    font-size: 0.72rem;
    color: var(--sl-color-gray-3);
  }

  .ai-box__send {
    padding: 0.35rem 1rem;
    border-radius: 0.4rem;
    font-size: 0.82rem;
    font-weight: 600;
    background: var(--sl-color-accent);
    color: var(--sl-color-accent-high);
    border: none;
    cursor: pointer;
    transition: opacity 0.15s;
  }

  .ai-box__send:hover:not(:disabled) {
    opacity: 0.85;
  }

  .ai-box__send:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
