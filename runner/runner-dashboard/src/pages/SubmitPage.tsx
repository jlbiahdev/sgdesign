import { SubmitForm } from '@/components/SubmitForm'
import { Link } from 'react-router-dom'

export function SubmitPage() {
  return (
    <div>
      <Link to="/" className="back-link">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <polyline points="15 18 9 12 15 6"/>
        </svg>
        Retour au dashboard
      </Link>
      <SubmitForm />
    </div>
  )
}
