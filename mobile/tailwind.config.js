/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        bg: {
          DEFAULT: '#0a0a0a',
          card: '#1a1a1a',
          elevated: '#242424',
        },
        accent: {
          DEFAULT: '#e8b84b',
          hover: '#f0c668',
        },
        status: {
          pending: '#ef4444',
          progress: '#eab308',
          done: '#22c55e',
        },
      },
    },
  },
  plugins: [],
}
