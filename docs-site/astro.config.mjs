// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import svelte from '@astrojs/svelte';

export default defineConfig({
    site: 'https://aadhii-yz.github.io',
    base: '/PocketLedger',
    integrations: [
        starlight({
            title: 'PocketLedger',
            description: 'Multi-location inventory and billing for retail businesses.',
            social: [
                { icon: 'github', label: 'GitHub', href: 'https://github.com/aadhii-yz/PocketLedger' },
            ],
            editLink: {
                baseUrl: 'https://github.com/aadhii-yz/PocketLedger/edit/master/docs-site/',
            },
            components: {
                Footer: './src/components/AiFooter.astro',
            },
            sidebar: [
                { label: 'Getting Started', slug: 'getting-started' },
                {
                    label: 'Installation',
                    items: [
                        { label: 'Companion App', slug: 'installation/companion-app' },
                        { label: 'Linux', slug: 'installation/linux' },
                        { label: 'Windows', slug: 'installation/windows' },
                        { label: 'Android', slug: 'installation/android' },
                    ],
                },
                {
                    label: 'User Guide',
                    items: [
                        { label: 'Billing / POS', slug: 'user-guide/billing' },
                        { label: 'Inventory', slug: 'user-guide/stock' },
                        { label: 'Stock Transfers', slug: 'user-guide/transfers' },
                        { label: 'Manager', slug: 'user-guide/manager' },
                        { label: 'Admin', slug: 'user-guide/admin' },
                        { label: 'Print Settings', slug: 'user-guide/print-settings' },
                    ],
                },
                {
                    label: 'Printers',
                    items: [
                        { label: 'Hardware Overview', slug: 'printers' },
                        { label: 'WiFi Setup (LP46)', slug: 'printers/wifi-setup' },
                    ],
                },
                {
                    label: 'Troubleshooting',
                    items: [
                        { label: 'Overview', slug: 'troubleshooting' },
                        { label: 'Printing Issues', slug: 'troubleshooting/printing' },
                        { label: 'Connection Issues', slug: 'troubleshooting/connection' },
                    ],
                },
            ],
            head: [
                {
                    tag: 'link',
                    attrs: { rel: 'alternate', type: 'text/plain', title: 'LLM-friendly docs', href: '/PocketLedger/llms.txt' },
                },
            ],
        }),
        svelte(),
    ],
});
