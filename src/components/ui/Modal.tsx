import { ReactNode, useEffect } from 'react'

export function Modal({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
}) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [open, onClose])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-end sm:items-center justify-center"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        className="w-full sm:max-w-md bg-bg-card border border-border sm:rounded-2xl rounded-t-3xl p-5 pb-safe max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between mb-3">
          {title && <h2 className="text-lg font-semibold">{title}</h2>}
          <button
            onClick={onClose}
            aria-label="Close"
            className="ml-auto w-9 h-9 -mt-1 -mr-2 rounded-full hover:bg-bg-elevated text-neutral-400 flex items-center justify-center"
          >
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}
