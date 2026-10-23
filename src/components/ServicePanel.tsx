import { useState } from 'react'
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
} from 'wagmi'
import { Loader2, ExternalLink } from 'lucide-react'
import { toast } from 'sonner'
import { AGENT_TAB_ABI, AGENT_TAB_ADDRESS } from '../agentTabContract'
import { NETWORK, buildTxUrl } from '../networkConfig'
import { parseAmount } from '@/onchain-money'

const CHAIN_ID = NETWORK.chainId

const glass = {
  inner: {
    background: 'var(--surface-muted)',
    borderRadius: '1rem',
    border: '1px solid var(--border)',
  } as React.CSSProperties,
}

function TxLink({ hash }: { hash: string }) {
  return (
    <a
      href={buildTxUrl(hash)}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-1 text-xs font-medium"
      style={{ color: 'var(--accent-hover)' }}
    >
      View on explorer <ExternalLink className="size-3" />
    </a>
  )
}

export function ServicePanel() {
  const { address, chainId } = useAccount()
  const { switchChain } = useSwitchChain()

  const [tabId, setTabId] = useState('')
  const [cumAmount, setCumAmount] = useState('')
  const [sig, setSig] = useState('')

  const wrongChain = chainId !== CHAIN_ID

  const {
    writeContract: redeem,
    data: redeemHash,
    isPending,
    isError,
    error,
    reset,
  } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: redeemHash,
    chainId: CHAIN_ID,
  })

  const handleRedeem = () => {
    if (!address) return toast.error('Connect your wallet first')
    if (wrongChain) {
      switchChain({ chainId: CHAIN_ID })
      return
    }
    if (!tabId || !cumAmount || !sig) return toast.error('Fill in all fields')

    let parsedCum: bigint
    try {
      parsedCum = parseAmount(CHAIN_ID, cumAmount).raw
    } catch {
      toast.error('Invalid amount')
      return
    }

    redeem({
      address: AGENT_TAB_ADDRESS,
      abi: AGENT_TAB_ABI,
      functionName: 'redeem',
      args: [tabId as `0x${string}`, parsedCum, sig as `0x${string}`],
      chainId: CHAIN_ID,
    })
  }

  const errMsg = isError
    ? (() => {
        const m = (error?.message ?? '').toLowerCase()
        if (m.includes('user rejected')) return null
        if (m.includes('bad sig')) return 'Invalid signature: must be signed by the payer for this tab.'
        if (m.includes('no new amount')) return 'This voucher has already been fully redeemed.'
        if (m.includes('not service')) return 'Your address is not the service for this tab.'
        if (m.includes('grace ended')) return 'The tab has expired and the grace period has ended.'
        if (m.includes('tab closed')) return 'This tab is already closed.'
        return 'Transaction failed. Check the tab ID and signature.'
      })()
    : null

  return (
    <div className="space-y-4">
      <div style={glass.inner} className="p-4 space-y-3">
        <div>
          <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
            Tab ID (bytes32)
          </label>
          <input
            value={tabId}
            onChange={(e) => setTabId(e.target.value)}
            placeholder="0x..."
            className="mono w-full rounded-xl px-3 py-2 text-xs outline-none"
            style={{
              background: 'var(--surface-strong)',
              border: '1px solid var(--border)',
              color: 'var(--ink)',
            }}
          />
        </div>
        <div>
          <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
            Cumulative amount (USDC)
          </label>
          <input
            inputMode="decimal"
            value={cumAmount}
            onChange={(e) => {
              const v = e.target.value.replace(/[^0-9.]/g, '')
              if (v === '' || /^\d*\.?\d*$/.test(v)) setCumAmount(v)
            }}
            placeholder="5.00"
            className="display w-full rounded-xl px-3 py-2 text-2xl font-bold tabular-nums outline-none"
            style={{
              background: 'var(--surface-strong)',
              border: '1px solid var(--border)',
              color: 'var(--ink)',
            }}
          />
          <p className="mt-1 text-xs" style={{ color: 'var(--subtle)' }}>
            The total from the voucher, not just this increment.
          </p>
        </div>
        <div>
          <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
            Payer signature
          </label>
          <textarea
            value={sig}
            onChange={(e) => setSig(e.target.value)}
            rows={3}
            placeholder="0x... (paste the signature from the payer)"
            className="mono w-full rounded-xl px-3 py-2 text-xs outline-none resize-none"
            style={{
              background: 'var(--surface-strong)',
              border: '1px solid var(--border)',
              color: 'var(--ink)',
            }}
          />
        </div>
      </div>

      <button
        disabled={isPending || isConfirming || !address}
        onClick={handleRedeem}
        className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white transition-all hover:scale-[1.01] active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
        style={{ background: 'var(--accent)' }}
      >
        {isPending ? (
          <span className="flex items-center justify-center gap-2">
            <Loader2 className="size-4 animate-spin" /> Confirm in wallet...
          </span>
        ) : isConfirming ? (
          <span className="flex items-center justify-center gap-2">
            <Loader2 className="size-4 animate-spin" /> Confirming...
          </span>
        ) : !address ? (
          'Connect wallet'
        ) : wrongChain ? (
          `Switch to ${NETWORK.name}`
        ) : (
          'Redeem Voucher'
        )}
      </button>

      {errMsg && (
        <div className="rounded-2xl p-3 text-xs" style={{ background: 'rgba(186,43,76,0.08)', color: 'var(--danger)' }}>
          {errMsg}
        </div>
      )}

      {isSuccess && redeemHash && (
        <div className="rounded-2xl p-3 space-y-1" style={{ background: 'rgba(26,128,71,0.08)' }}>
          <p className="text-xs font-semibold" style={{ color: 'var(--success)' }}>Voucher redeemed</p>
          <TxLink hash={redeemHash} />
          <button
            className="text-xs font-medium mt-1 block"
            style={{ color: 'var(--muted)' }}
            onClick={() => { reset(); setTabId(''); setCumAmount(''); setSig('') }}
          >
            Redeem another
          </button>
        </div>
      )}
    </div>
  )
}
