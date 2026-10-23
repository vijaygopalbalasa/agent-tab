import { useState } from 'react'
import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { TokenUSDC } from '@web3icons/react'
import { PayerPanel } from './components/PayerPanel'
import { ServicePanel } from './components/ServicePanel'
import { TabView } from './components/TabView'
import { NETWORK, buildAddressUrl } from './networkConfig'
import { ExternalLink } from 'lucide-react'

const CONTRACT_ADDR = NETWORK.contractAddress

export default function App() {
  const { address } = useAccount()
  const [mainTab, setMainTab] = useState<'payer' | 'service' | 'view'>('payer')

  return (
    <div
      className="min-h-dvh"
      style={{
        background: 'var(--bg-gradient)',
      }}
    >
      {/* Header */}
      <header
        className="sticky top-0 z-20 px-4 py-3 flex items-center justify-between"
        style={{
          background: 'rgba(255,255,255,0.75)',
          backdropFilter: 'blur(20px) saturate(180%)',
          WebkitBackdropFilter: 'blur(20px) saturate(180%)',
          borderBottom: '1px solid var(--border)',
        }}
      >
        <div className="flex items-center gap-2">
          <div
            className="flex size-8 items-center justify-center rounded-xl"
            style={{ background: 'var(--accent)' }}
          >
            <TokenUSDC size={18} variant="mono" className="text-white" />
          </div>
          <div>
            <h1 className="display text-base font-bold leading-tight" style={{ color: 'var(--ink)' }}>
              Agent Tab
            </h1>
            <p className="text-xs" style={{ color: 'var(--subtle)' }}>
              {NETWORK.name}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <a
            href={buildAddressUrl(CONTRACT_ADDR)}
            target="_blank"
            rel="noreferrer"
            className="hidden sm:inline-flex items-center gap-1 rounded-xl px-2.5 py-1.5 text-xs font-medium"
            style={{
              background: 'var(--surface-muted)',
              color: 'var(--muted)',
              border: '1px solid var(--border)',
            }}
          >
            Contract <ExternalLink className="size-3" />
          </a>
          <ConnectKitButton />
        </div>
      </header>

      {/* Main content */}
      <main className="mx-auto max-w-lg px-4 py-6 space-y-4">
        {/* Hero */}
        <section
          className="rounded-3xl p-5"
          style={{
            background: 'var(--surface-strong)',
            backdropFilter: 'blur(24px) saturate(180%)',
            WebkitBackdropFilter: 'blur(24px) saturate(180%)',
            border: '1px solid var(--border)',
          }}
        >
          <p className="text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
            AGENT TAB
          </p>
          <p className="display text-2xl font-bold leading-snug" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>
            Prepaid USDC tabs for agent payments
          </p>
          <p className="mt-2 text-sm" style={{ color: 'var(--ink-2)' }}>
            Payers fund a tab; services draw from it using signed vouchers. Unused funds return after expiry.
          </p>
          {address && (
            <p className="mt-3 text-xs font-medium tabular-nums" style={{ color: 'var(--subtle)' }}>
              Connected: {address.slice(0, 6)}...{address.slice(-4)}
            </p>
          )}
        </section>

        {/* Tab switcher */}
        <div
          className="flex rounded-2xl p-1 gap-1"
          style={{
            background: 'var(--surface-strong)',
            border: '1px solid var(--border)',
          }}
        >
          {([
            { key: 'payer', label: 'Payer' },
            { key: 'service', label: 'Service' },
            { key: 'view', label: 'Lookup Tab' },
          ] as const).map(({ key, label }) => (
            <button
              key={key}
              onClick={() => setMainTab(key)}
              className="flex-1 rounded-xl py-2.5 text-sm font-semibold transition-all"
              style={{
                background: mainTab === key ? 'var(--accent)' : 'transparent',
                color: mainTab === key ? '#fff' : 'var(--subtle)',
              }}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Panel content */}
        <section
          className="rounded-3xl p-5"
          style={{
            background: 'var(--surface-strong)',
            backdropFilter: 'blur(24px) saturate(180%)',
            WebkitBackdropFilter: 'blur(24px) saturate(180%)',
            border: '1px solid var(--border)',
          }}
        >
          {mainTab === 'payer' && (
            <>
              <h2 className="display text-base font-bold mb-4" style={{ color: 'var(--ink)' }}>Payer</h2>
              <PayerPanel />
            </>
          )}
          {mainTab === 'service' && (
            <>
              <h2 className="display text-base font-bold mb-4" style={{ color: 'var(--ink)' }}>Service: Redeem Voucher</h2>
              <ServicePanel />
            </>
          )}
          {mainTab === 'view' && (
            <>
              <h2 className="display text-base font-bold mb-4" style={{ color: 'var(--ink)' }}>Lookup Tab</h2>
              <TabView />
            </>
          )}
        </section>

        {/* How it works */}
        <section
          className="rounded-3xl p-5 space-y-3"
          style={{
            background: 'var(--surface-muted)',
            border: '1px solid var(--border)',
          }}
        >
          <h3 className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--subtle)' }}>How it works</h3>
          <ol className="space-y-2 text-sm" style={{ color: 'var(--ink-2)' }}>
            <li className="flex gap-2">
              <span className="font-bold tabular-nums" style={{ color: 'var(--accent)', minWidth: '1rem' }}>1.</span>
              <span>Payer opens a tab, setting the service address, USDC amount, and expiry.</span>
            </li>
            <li className="flex gap-2">
              <span className="font-bold tabular-nums" style={{ color: 'var(--accent)', minWidth: '1rem' }}>2.</span>
              <span>Payer signs vouchers off-chain with a running cumulative total.</span>
            </li>
            <li className="flex gap-2">
              <span className="font-bold tabular-nums" style={{ color: 'var(--accent)', minWidth: '1rem' }}>3.</span>
              <span>Service redeems vouchers on-chain; only the incremental difference is paid per call.</span>
            </li>
            <li className="flex gap-2">
              <span className="font-bold tabular-nums" style={{ color: 'var(--accent)', minWidth: '1rem' }}>4.</span>
              <span>After expiry plus a 1-hour grace period, anyone can close the tab and return the unused balance to the payer.</span>
            </li>
          </ol>
        </section>
      </main>
    </div>
  )
}
