import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const noPwa = process.env.NO_PWA === '1';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit(),
		!noPwa && VitePWA({
			registerType: 'autoUpdate',
			injectRegister: null,
			manifest: {
				name: 'PocketLedger',
				short_name: 'PocketLedger',
				description: 'Point-of-sale and inventory management',
				theme_color: '#8B2635',
				background_color: '#ffffff',
				display: 'standalone',
				scope: '/',
				start_url: '/',
				icons: [
					{ src: '/icons/icon-192x192.png', sizes: '192x192', type: 'image/png' },
					{
						src: '/icons/icon-512x512.png',
						sizes: '512x512',
						type: 'image/png',
						purpose: 'any maskable'
					}
				]
			},
			workbox: {
				globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
				runtimeCaching: [
					{
						urlPattern: /^\/api\/collections\/(products|categories|locations)\/records/i,
						handler: 'StaleWhileRevalidate',
						options: {
							cacheName: 'reference-data',
							expiration: { maxEntries: 200, maxAgeSeconds: 5 * 60 }
						}
					},
					{
						urlPattern: /^\/api\/collections\/stock\/records/i,
						handler: 'NetworkOnly'
					},
					{
						urlPattern: /^\/api\/custom\/.*/i,
						handler: 'NetworkOnly'
					}
				]
			}
		})
	].filter(Boolean)
});
