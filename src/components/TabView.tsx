import { useState } from 'react'
import { useReadContract } from 'wagmi'
import { ExternalLink, Search } from 'lucide-react'
import { AGENT_TAB_ABI, AGENT_TAB_ADDRESS } from '../agentTabContract'
import { NETWORK, buildAddressUrl } from '../networkConfig'
import { Amount, usdcDecimalsFor } from '@/onchain-money'

function fmtUsdc(raw: bigint): string {
  return Amount.fromRaw(raw, usdcDecimalsFor(NETWORK.chainId)).toFixed(2)
}

const CHAIN_ID = NETWORK.chainId

const glass = {
  inner: {
    background: 'var(--surface-muted)',
    borderRadius: '1rem',
    border: '1px solid var(--border)',
  } as React.CSSProperties,
}

function AddrLink({ addr }: { addr: string }) {
  return (
    <a
      href={buildAddressUrl(addr)}
      target="_blank"
      rel="noreferrer"
      className="mono text-xs inline-flex items-center gap-0.5 hover:underline"
      style={{ color: 'var(--accent-hover)' }}
    >
      {addr.slice(0, 6)}...{addr.slice(-4)}
      <ExternalLink className="size-2.5" />
    </a>
  )
}

function getTabStatusLabel(closed: boolean, expiresAt: bigint): string {
  const nowSec = BigInt(Math.floor(Date.now() / 1000))
  if (closed) return 'Closed'
  if (nowSec > expiresAt + 3600n) return 'Closeable'
  if (nowSec > expiresAt) return 'In grace'
  if (nowSec > expiresAt - 3600n) return 'Expiring soon'
  return 'Active'
}

function TabStatus({ closed, expiresAt }: { closed: boolean; expiresAt: bigint }) {
  const label = getTabStatusLabel(closed, expiresAt)
  const styleMap: Record<string, React.CSSProperties> = {
    Closed: { background: 'rgba(107,101,128,0.15)', color: 'var(--muted)' },
    Closeable: { background: 'rgba(186,43,76,0.12)', color: 'var(--danger)' },
    'In grace': { background: 'rgba(186,43,76,0.08)', color: 'var(--danger)' },
    'Expiring soon': { background: 'rgba(255,160,0,0.12)', color: '#b45309' },
    Active: { background: 'rgba(26,128,71,0.12)', color: 'var(--success)' },
  }
  return <span className="text-xs font-semibold px-2 py-0.5 rounded-full" style={styleMap[label] ?? styleMap.Active}>{label}</span>
}

export function TabView() {
  const [tabId, setTabId] = useState('')
  const [query, setQuery] = useState('')

  const { data: tab, isLoading, error } = useReadContract({
    address: AGENT_TAB_ADDRESS,
    abi: AGENT_TAB_ABI,
    functionName: 'getTab',
    args: [query as `0x${string}`],
    chainId: CHAIN_ID,
    query: { enabled: query.length === 66 && query.startsWith('0x') },
  })

  const fmt = (v: bigint) => fmtUsdc(v)

  const handleSearch = () => {
    if (tabId.length === 66 && tabId.startsWith('0x')) {
      setQuery(tabId)
    }
  }

  interface TabData { payer: string; service: string; balance: bigint; redeemed: bigint; expiresAt: bigint; closed: boolean }
  const zeroAddr = '0x0000000000000000000000000000000000000000'
  const t = tab as TabData | undefined
  const tabExists = t && t.payer !== zeroAddr

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <input
          value={tabId}
          onChange={(e) => setTabId(e.target.value)}
          placeholder="0x... (tab ID, 66 hex chars)"
          className="mono flex-1 rounded-xl px-3 py-2 text-xs outline-none"
          style={{
            background: 'var(--surface-strong)',
            border: '1px solid var(--border)',
            color: 'var(--ink)',
          }}
          onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
        />
        <button
          onClick={handleSearch}
          className="rounded-xl px-4 py-2 text-sm font-semibold text-white"
          style={{ background: 'var(--accent)' }}
        >
          <Search className="size-4" />
        </button>
      </div>

      {isLoading && (
        <div className="text-center text-sm py-4" style={{ color: 'var(--muted)' }}>Looking up tab...</div>
      )}

      {error && (
        <div className="rounded-2xl p-3 text-xs" style={{ background: 'rgba(186,43,76,0.08)', color: 'var(--danger)' }}>
          Query failed. Check the tab ID.
        </div>
      )}

      {query && !isLoading && !tabExists && !error && (
        <div className="rounded-2xl p-4 text-sm text-center" style={{ background: 'var(--surface-muted)', color: 'var(--muted)' }}>
          No tab found for this ID.
        </div>
      )}

      {tabExists && t && (
        <div className="rounded-2xl p-4 space-y-3" style={glass.inner}>
          <div className="flex items-start justify-between">
            <p className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>Tab details</p>
            <TabStatus closed={t.closed} expiresAt={t.expiresAt} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <p className="text-xs font-semibold mb-0.5" style={{ color: 'var(--subtle)' }}>Payer</p>
              <AddrLink addr={t.payer} />
            </div>
            <div>
              <p className="text-xs font-semibold mb-0.5" style={{ color: 'var(--subtle)' }}>Service</p>
              <AddrLink addr={t.service} />
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3 pt-1">
            <div className="rounded-xl p-3 text-center" style={{ background: 'var(--surface-strong)', border: '1px solid var(--border)' }}>
              <p className="text-xs font-semibold mb-1" style={{ color: 'var(--subtle)' }}>Funded</p>
              <p className="display text-xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
                {fmt(t.balance + t.redeemed)}
              </p>
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>USDC</p>
            </div>
            <div className="rounded-xl p-3 text-center" style={{ background: 'var(--surface-strong)', border: '1px solid var(--border)' }}>
              <p className="text-xs font-semibold mb-1" style={{ color: 'var(--subtle)' }}>Redeemed</p>
              <p className="display text-xl font-bold tabular-nums" style={{ color: 'var(--success)' }}>
                {fmt(t.redeemed)}
              </p>
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>USDC</p>
            </div>
            <div className="rounded-xl p-3 text-center" style={{ background: 'var(--surface-strong)', border: '1px solid var(--border)' }}>
              <p className="text-xs font-semibold mb-1" style={{ color: 'var(--subtle)' }}>Remaining</p>
              <p className="display text-xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
                {fmt(t.balance)}
              </p>
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>USDC</p>
            </div>
          </div>

          <div className="pt-1">
            <p className="text-xs font-semibold mb-0.5" style={{ color: 'var(--subtle)' }}>Expires</p>
            <p className="text-sm font-medium" style={{ color: 'var(--ink-2)' }}>
              {new Date(Number(t.expiresAt) * 1000).toLocaleString()}
            </p>
          </div>
        </div>
      )}
    </div>
  )
}
