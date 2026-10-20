import version from "../../contract/version.json" with { type: "json" };

/// The single source is `sync/contract/version.json`.
export const CONTRACT = version.contract;
export const MIN_READABLE = version.minReadable;
