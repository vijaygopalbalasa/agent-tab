import { useState, useCallback, useEffect } from 'react'
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useSwitchChain,
  useSignTypedData,
} from 'wagmi'
import { erc20Abi, parseAbi, parseEventLogs } from 'viem'
import { Loader2, ExternalLink, Copy, Check } from 'lucide-react'
import { toast } from 'sonner'
import { AGENT_TAB_ABI, AGENT_TAB_ADDRESS, VOUCHER_TYPES } from '../agentTabContract'
import { NETWORK, buildTxUrl } from '../networkConfig'
import { parseAmount, Amount, usdcDecimalsFor } from '@/onchain-money'

function fmtUsdc(chainId: number, raw: bigint): string {
  return Amount.fromRaw(raw, usdcDecimalsFor(chainId)).toFixed(2)
}

const CHAIN_ID = NETWORK.chainId
const USDC = NETWORK.usdcAddress
const TAB_OPENED = parseAbi([
  'event TabOpened(bytes32 indexed tabId, address indexed payer, address indexed service, uint256 amount, uint256 expiresAt)',
])

const glass = {
  card: {
    background: 'var(--surface-strong)',
    backdropFilter: 'blur(24px) saturate(180%)',
    WebkitBackdropFilter: 'blur(24px) saturate(180%)',
    border: '1px solid var(--border)',
    borderRadius: '1.5rem',
  } as React.CSSProperties,
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

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false)
  const handleCopy = useCallback(() => {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }, [text])
  return (
    <button
      onClick={handleCopy}
      className="flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-medium transition-colors"
      style={{
        background: copied ? 'rgba(26,128,71,0.12)' : 'var(--surface-muted)',
        color: copied ? 'var(--success)' : 'var(--accent)',
        border: '1px solid var(--border)',
      }}
    >
      {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
      {copied ? 'Copied' : label}
    </button>
  )
}

// --- Open Tab sub-component ---
function OpenTabForm({ onOpened }: { onOpened: (tabId: string) => void }) {
  const { address, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const [service, setService] = useState('')
  const [amount, setAmount] = useState('')
  const [daysAhead, setDaysAhead] = useState('7')

  const wrongChain = chainId !== CHAIN_ID

  // Allowance check
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: USDC,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [address ?? '0x0000000000000000000000000000000000000000', AGENT_TAB_ADDRESS],
    chainId: CHAIN_ID,
    query: { enabled: !!address },
  })

  const parsedAmount = amount ? parseAmount(CHAIN_ID, amount) : null
  const needsApproval = parsedAmount && (allowance ?? 0n) < parsedAmount.raw

  // Approve
  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApprovePending,
    reset: resetApprove,
  } = useWriteContract()
  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } =
    useWaitForTransactionReceipt({ hash: approveTxHash, chainId: CHAIN_ID })

  // Once the approval lands, re-read the allowance so the next click opens the tab instead of approving again
  useEffect(() => {
    if (isApproveSuccess) void refetchAllowance()
  }, [isApproveSuccess, refetchAllowance])

  const handleApprove = () => {
    if (!parsedAmount) return
    approve({
      address: USDC,
      abi: erc20Abi,
      functionName: 'approve',
      args: [AGENT_TAB_ADDRESS, parsedAmount.raw],
      chainId: CHAIN_ID,
    })
  }

  // Open tab
  const {
    writeContract: openTab,
    data: openTxHash,
    isPending: isOpenPending,
    reset: resetOpen,
  } = useWriteContract()
  const { isLoading: isOpenConfirming, isSuccess: isOpenSuccess, data: openReceipt } =
    useWaitForTransactionReceipt({ hash: openTxHash, chainId: CHAIN_ID })

  // The new tab's id comes from its TabOpened event; the payer needs it to sign vouchers
  const openedTabId = openReceipt
    ? parseEventLogs({ abi: TAB_OPENED, logs: openReceipt.logs, eventName: 'TabOpened' })[0]?.args.tabId
    : undefined
  useEffect(() => {
    if (openedTabId) onOpened(openedTabId)
  }, [openedTabId, onOpened])

  const handleOpen = () => {
    if (!parsedAmount || !service) return
    const expiresAt = BigInt(Math.floor(Date.now() / 1000) + parseInt(daysAhead) * 86400)
    openTab({
      address: AGENT_TAB_ADDRESS,
      abi: AGENT_TAB_ABI,
      functionName: 'openTab',
      args: [service as `0x${string}`, parsedAmount.raw, expiresAt],
      chainId: CHAIN_ID,
    })
  }

  const handleAction = () => {
    if (wrongChain) {
      switchChain({ chainId: CHAIN_ID })
      return
    }
    if (needsApproval && !isApproveSuccess) {
      handleApprove()
    } else {
      handleOpen()
    }
  }

  const isPending = isApprovePending || isOpenPending
  const isConfirming = isApproveConfirming || isOpenConfirming

  const btnLabel = !address
    ? 'Connect wallet'
    : wrongChain
      ? `Switch to ${NETWORK.name}`
      : needsApproval && !isApproveSuccess
        ? 'Allow USDC'
        : isApproveSuccess && needsApproval
          ? 'Open Tab'
          : 'Open Tab'

  return (
    <div className="space-y-3">
      <div style={glass.inner} className="p-4 space-y-3">
        <div>
          <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
            Service address
          </label>
          <input
            value={service}
            onChange={(e) => setService(e.target.value)}
            placeholder="0x..."
            className="w-full rounded-xl px-3 py-2 text-sm font-medium outline-none"
            style={{
              background: 'var(--surface-strong)',
              border: '1px solid var(--border)',
              color: 'var(--ink)',
            }}
          />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
              Amount (USDC)
            </label>
            <input
              inputMode="decimal"
              value={amount}
              onChange={(e) => {
                const v = e.target.value.replace(/[^0-9.]/g, '')
                if (v === '' || /^\d*\.?\d*$/.test(v)) setAmount(v)
              }}
              placeholder="10.00"
              className="display w-full rounded-xl px-3 py-2 text-2xl font-bold tabular-nums outline-none"
              style={{
                background: 'var(--surface-strong)',
                border: '1px solid var(--border)',
                color: 'var(--ink)',
              }}
            />
          </div>
          <div>
            <label className="block text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>
              Expires in (days)
            </label>
            <input
              inputMode="numeric"
              value={daysAhead}
              onChange={(e) => setDaysAhead(e.target.value.replace(/[^0-9]/g, ''))}
              placeholder="7"
              className="display w-full rounded-xl px-3 py-2 text-2xl font-bold tabular-nums outline-none"
              style={{
                background: 'var(--surface-strong)',
                border: '1px solid var(--border)',
                color: 'var(--ink)',
              }}
            />
          </div>
        </div>
      </div>

      <button
        disabled={isPending || isConfirming || !address}
        onClick={handleAction}
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
        ) : (
          btnLabel
        )}
      </button>

      {isApproveSuccess && (
        <div className="rounded-2xl p-3 text-xs text-center" style={{ background: 'rgba(26,128,71,0.08)', color: 'var(--success)' }}>
          USDC approved. Click Open Tab to fund the tab.
        </div>
      )}
      {isOpenSuccess && openTxHash && (
        <div className="rounded-2xl p-3 space-y-1" style={{ background: 'rgba(26,128,71,0.08)' }}>
          <p className="text-xs font-semibold" style={{ color: 'var(--success)' }}>Tab opened successfully</p>
          {openedTabId && (
            <div className="flex items-center gap-2">
              <span className="mono text-xs break-all" style={{ color: 'var(--ink)' }} data-testid="opened-tab-id">{openedTabId}</span>
              <CopyButton text={openedTabId} label="Copy tab ID" />
            </div>
          )}
          <TxLink hash={openTxHash} />
          <button
            className="text-xs font-medium mt-1"
            style={{ color: 'var(--muted)' }}
            onClick={() => { resetApprove(); resetOpen(); setAmount(''); setService('') }}
          >
            Open another tab
          </button>
        </div>
      )}
      {approveTxHash && isApproveConfirming && (
        <p className="text-xs text-center" style={{ color: 'var(--muted)' }}>
          Approving USDC... <TxLink hash={approveTxHash} />
        </p>
      )}
      {isApproveSuccess && !needsApproval && (
        <p className="text-xs text-center" style={{ color: 'var(--subtle)' }}>
          After opening, refetch allowance: <button className="underline" onClick={() => { void refetchAllowance() }}>refresh</button>
        </p>
      )}
    </div>
  )
}

// --- Sign Voucher sub-component ---
function SignVoucherForm({ initialTabId }: { initialTabId: string }) {
  const { address, chainId } = useAccount()
  const { signTypedDataAsync } = useSignTypedData()
  const [tabId, setTabId] = useState(initialTabId)
  const [cumAmount, setCumAmount] = useState('')
  const [sig, setSig] = useState('')
  const [signing, setSigning] = useState(false)

  const wrongChain = chainId !== CHAIN_ID

  const handleSign = async () => {
    if (!address || !tabId || !cumAmount) return
    if (wrongChain) return toast.error(`Switch to ${NETWORK.name} first`)
    const parsedCum = parseAmount(CHAIN_ID, cumAmount)
    setSigning(true)
    try {
      const signature = await signTypedDataAsync({
        domain: {
          name: 'AgentTab',
          version: '1',
          chainId: CHAIN_ID,
          verifyingContract: AGENT_TAB_ADDRESS,
        },
        types: VOUCHER_TYPES,
        primaryType: 'Voucher',
        message: {
          tabId: tabId as `0x${string}`,
          cumulativeAmount: parsedCum.raw,
        },
      })
      setSig(signature)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      if (!msg.toLowerCase().includes('user rejected')) {
        toast.error('Signing failed')
      }
    } finally {
      setSigning(false)
    }
  }

  return (
    <div className="space-y-3">
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
            Cumulative amount (USDC total so far)
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
            Total the service may have received, not just this payment.
          </p>
        </div>
      </div>
      <button
        disabled={signing || !address || !tabId || !cumAmount}
        onClick={() => { void handleSign() }}
        className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white transition-all hover:scale-[1.01] active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
        style={{ background: 'var(--accent)' }}
      >
        {signing ? (
          <span className="flex items-center justify-center gap-2">
            <Loader2 className="size-4 animate-spin" /> Sign in wallet...
          </span>
        ) : (
          'Sign Voucher'
        )}
      </button>
      {sig && (
        <div className="rounded-2xl p-3 space-y-2" style={{ background: 'rgba(26,128,71,0.07)' }}>
          <p className="text-xs font-semibold" style={{ color: 'var(--success)' }}>Voucher signed. Share this with the service.</p>
          <div className="rounded-xl p-2 text-xs break-all" style={{ background: 'var(--surface-muted)', color: 'var(--ink-2)', fontFamily: 'monospace' }}>
            {sig}
          </div>
          <CopyButton text={sig} label="Copy signature" />
        </div>
      )}
    </div>
  )
}

// --- Claimable / Withdraw sub-component ---
function ClaimableSection() {
  const { address, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const wrongChain = chainId !== CHAIN_ID

  const { data: claimableRaw, refetch } = useReadContract({
    address: AGENT_TAB_ADDRESS,
    abi: AGENT_TAB_ABI,
    functionName: 'claimable',
    args: [address ?? '0x0000000000000000000000000000000000000000'],
    chainId: CHAIN_ID,
    query: { enabled: !!address },
  })

  const claimable = (claimableRaw as bigint | undefined) ?? 0n
  const formatted = claimable > 0n
    ? fmtUsdc(CHAIN_ID, claimable)
    : '0.00'

  const { writeContract: withdraw, data: withdrawHash, isPending, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: withdrawHash, chainId: CHAIN_ID })

  const handleWithdraw = () => {
    if (wrongChain) {
      switchChain({ chainId: CHAIN_ID })
      return
    }
    withdraw({
      address: AGENT_TAB_ADDRESS,
      abi: AGENT_TAB_ABI,
      functionName: 'withdraw',
      chainId: CHAIN_ID,
    })
  }

  if (!address) return null

  return (
    <div className="rounded-2xl p-4 space-y-3" style={glass.inner}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>Claimable balance</p>
          <p className="display text-2xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
            {formatted} <span className="text-sm font-medium" style={{ color: 'var(--subtle)' }}>USDC</span>
          </p>
          <p className="text-xs mt-0.5" style={{ color: 'var(--subtle)' }}>Fallback for blocked transfers</p>
        </div>
        <button
          onClick={() => { void refetch() }}
          className="text-xs font-medium px-2 py-1 rounded-lg"
          style={{ background: 'var(--surface-strong)', color: 'var(--muted)', border: '1px solid var(--border)' }}
        >
          Refresh
        </button>
      </div>
      {claimable > 0n && (
        <>
          <button
            disabled={isPending || isConfirming}
            onClick={handleWithdraw}
            className="w-full rounded-xl py-2.5 text-sm font-semibold text-white disabled:opacity-40"
            style={{ background: 'var(--success)' }}
          >
            {isPending ? <span className="flex items-center justify-center gap-2"><Loader2 className="size-4 animate-spin" /> Confirm...</span>
              : isConfirming ? <span className="flex items-center justify-center gap-2"><Loader2 className="size-4 animate-spin" /> Confirming...</span>
                : `Withdraw ${formatted} USDC`}
          </button>
          {isSuccess && withdrawHash && (
            <div className="text-xs" style={{ color: 'var(--success)' }}>
              Withdrawn. <TxLink hash={withdrawHash} /> <button className="underline ml-2" style={{ color: 'var(--muted)' }} onClick={() => { reset(); void refetch() }}>Reset</button>
            </div>
          )}
        </>
      )}
    </div>
  )
}

// --- Main PayerPanel ---
export function PayerPanel() {
  const [tab, setTab] = useState<'open' | 'sign'>('open')
  const [lastTabId, setLastTabId] = useState('')

  return (
    <div className="space-y-4">
      {/* Sub-tab switcher */}
      <div className="flex rounded-xl p-1 gap-1" style={{ background: 'var(--surface-muted)' }}>
        {(['open', 'sign'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="flex-1 rounded-lg py-2 text-sm font-semibold transition-colors"
            style={{
              background: tab === t ? 'var(--surface-strong)' : 'transparent',
              color: tab === t ? 'var(--ink)' : 'var(--subtle)',
              border: tab === t ? '1px solid var(--border)' : '1px solid transparent',
            }}
          >
            {t === 'open' ? 'Open Tab' : 'Sign Voucher'}
          </button>
        ))}
      </div>

      {tab === 'open' ? <OpenTabForm onOpened={setLastTabId} /> : <SignVoucherForm initialTabId={lastTabId} />}

      <ClaimableSection />
    </div>
  )
}
