/**
 * AgentTab contract ABI and address config.
 * ABI is imported from the Foundry artifact at build time.
 */
import artifact from '../contracts/out/AgentTab.sol/AgentTab.json';
import { NETWORK } from './networkConfig';

export const AGENT_TAB_ABI = artifact.abi;

export const AGENT_TAB_ADDRESS = NETWORK.contractAddress;

/** EIP-712 Voucher type definition for wagmi signTypedData */
export const VOUCHER_TYPES = {
  Voucher: [
    { name: 'tabId', type: 'bytes32' },
    { name: 'cumulativeAmount', type: 'uint256' },
  ],
} as const;
