/**
 * Network configuration for AgentTab.
 * Switch between Arc Testnet and Arc Mainnet by setting VITE_NETWORK.
 *   VITE_NETWORK=ARC-TESTNET  (default)
 *   VITE_NETWORK=ARC-MAINNET
 * The contract address is set per network in the NETWORKS map below.
 */

export type NetworkKey = 'ARC-TESTNET' | 'ARC-MAINNET';

const VITE_NETWORK = import.meta.env.VITE_NETWORK as string | undefined;
export const ACTIVE_NETWORK: NetworkKey =
  VITE_NETWORK === 'ARC-MAINNET' ? 'ARC-MAINNET' : 'ARC-TESTNET';

export interface NetworkConfig {
  chainId: number;
  name: string;
  rpcUrl: string;
  explorerBase: string;
  /** Block explorer base for testnet arcscan (https://testnet.arcscan.app) or mainnet explorer */
  arcscanBase: string;
  usdcAddress: `0x${string}`;
  contractAddress: `0x${string}`;
  isTestnet: boolean;
}

export const NETWORKS: Record<NetworkKey, NetworkConfig> = {
  'ARC-TESTNET': {
    chainId: 5042002,
    name: 'Arc Testnet',
    rpcUrl: 'https://rpc.testnet.arc.io',
    explorerBase: 'https://explorer.testnet.arc.io',
    arcscanBase: 'https://testnet.arcscan.app',
    usdcAddress: '0x3600000000000000000000000000000000000000',
    // Deployed 2026-10-23 -- replace with new address if redeployed
    contractAddress: '0x57a4c16047e36efb1dcf5fb51621b95ee3646d3a',
    isTestnet: true,
  },
  'ARC-MAINNET': {
    chainId: 5042,
    name: 'Arc',
    rpcUrl: 'https://rpc.mainnet.arc.io',
    explorerBase: 'https://explorer.arc.io',
    arcscanBase: 'https://explorer.arc.io',
    usdcAddress: '0x3600000000000000000000000000000000000000',
    // Deployed 2026-10-23, Sourcify exact match
    contractAddress: '0x9c984c55a585f5360fcaab5fde6d8bfcab02aa91',
    isTestnet: false,
  },
};

export const NETWORK = NETWORKS[ACTIVE_NETWORK];

export function buildTxUrl(txHash: string): string {
  return `${NETWORK.explorerBase}/tx/${txHash}`;
}

export function buildAddressUrl(address: string): string {
  return `${NETWORK.explorerBase}/address/${address}`;
}
