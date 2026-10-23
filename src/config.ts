/**
 * wagmi configuration
 * Built with Arc Studio -- https://studio.arc.io
 *
 * Arc Testnet: chain ID 5042002
 * Arc Mainnet: chain ID 5042 (USDC as native gas, explorer https://explorer.arc.io)
 *
 * Select the active network via VITE_NETWORK env var:
 *   ARC-TESTNET (default) or ARC-MAINNET
 */

import { http, createConfig } from 'wagmi'
import { mainnet } from 'wagmi/chains'
import { arcTestnet } from 'viem/chains'
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'
import { ACTIVE_NETWORK } from './networkConfig'

// Arc Mainnet as a custom wagmi/viem chain definition
const arcMainnet = {
  id: 5042,
  name: 'Arc',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.mainnet.arc.io'] },
  },
  blockExplorers: {
    default: { name: 'Arc Explorer', url: 'https://explorer.arc.io' },
  },
} as const

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(arcTestnet.id, arcTestnet.rpcUrls.default.http[0])
registerChain(arcMainnet.id, arcMainnet.rpcUrls.default.http[0])

const activeChain = ACTIVE_NETWORK === 'ARC-MAINNET' ? arcMainnet : arcTestnet

export const config = createConfig({
  chains: [activeChain, mainnet], // mainnet needed for ENS resolution
  connectors: [injected()],
  transports: {
    [arcTestnet.id]: http(),
    [arcMainnet.id]: http(),
    [mainnet.id]: http(), // ENS resolution uses mainnet
  },
})
