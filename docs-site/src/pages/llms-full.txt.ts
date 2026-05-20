import type { APIRoute } from 'astro';

// Concatenate all docs pages into a single AI-friendly text file.
// Generated at build time via import.meta.glob with raw file contents.
const rawFiles = import.meta.glob('../content/docs/**/*.{md,mdx}', {
    query: '?raw',
    import: 'default',
    eager: false,
}) as Record<string, () => Promise<string>>;

export const GET: APIRoute = async () => {
    const sorted = Object.entries(rawFiles).sort(([a], [b]) => a.localeCompare(b));

    const header = [
        '# PocketLedger — Full Documentation',
        '',
        'PocketLedger is a multi-location inventory and billing system for retail businesses.',
        'It consists of a Go/PocketBase backend, a SvelteKit PWA frontend, and a Flutter companion',
        'app that handles local thermal receipt and label printing via USB or WiFi.',
        '',
        '---',
        '',
    ].join('\n');

    const parts: string[] = [];
    for (const [path, load] of sorted) {
        const raw = await load();
        // Strip YAML frontmatter, keep everything after the closing ---
        const body = raw.replace(/^---[\s\S]*?---\n?/, '').trim();
        const slug = path
            .replace('../content/docs/', '')
            .replace(/\/index\.mdx?$/, '')
            .replace(/\.mdx?$/, '');
        parts.push(`## [${slug}]\n\n${body}`);
    }

    return new Response(header + parts.join('\n\n---\n\n'), {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
};
