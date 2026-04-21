/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: {
          DEFAULT: '#0a0a0a',
          card: '#1a1a1a',
          elevated: '#242424',
        },
        border: {
          DEFAULT: '#2a2a2a',
          strong: '#3a3a3a',
        },
        accent: {
          DEFAULT: '#e8b84b', // brass / amber — bar vibe
          hover: '#f0c668',
        },
        status: {
          pending: '#ef4444',
          progress: '#eab308',
          done: '#22c55e',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
