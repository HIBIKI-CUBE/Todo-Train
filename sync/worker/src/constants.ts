import constants from "./constants.json";

// Values must match sync/contract/constants.json (asserted by scripts/assert-golden.mjs).
export const OFFER_TTL_SECONDS = constants.offerTtlSeconds;
export const CONFIRM_OVERLAP_WINDOW_SECONDS = constants.confirmOverlapWindowSeconds;
export const CMD_FIFO_MAX = constants.cmdFifoMax;
