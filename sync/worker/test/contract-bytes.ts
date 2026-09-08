import type { WireEnvelope } from "../src/envelope.ts";

/** Golden wire bytes from sync/contract/http.json (putSnap / confirm / bind). */
export const X = "6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI";
export const Y = "UgKyT75SOaUjcnm8rdNOZvC3qC3oVkNtdt-WlgkO9rI";
export const S = "c1c2c3c4-d1d2-4e3e-8f4f-a5a6a7a8a9aa";
export const HMAC_IPHONE = "i4YEw3MQx6r36PyeMuX65fXGBexumZ_n0qqUZtYgQNg";
export const HMAC_MAC = "_Zwat9LFmivpBGJ2xzUc2J5kYqspRQSWqp856P5kl-8";

export const SNAP_TITLE = "週次レポート";

export const SNAP: WireEnvelope = {
  rev: 42,
  kind: "snap",
  n: "ha_Fwfr-03T8OAOV",
  ct: "NpGl3kGFaMKJ-e-egG5-rYgNQEuiFUUDlicTmvJesSCySoUrb7meW57CzPWi-VDlYHdHReDwgf6Jm2mtxd1pmuqfpHk6HIqZafcL1P-enL1O9TpXMg2QB8WUX2o7aUOmp7H5tIMmi5zkwjOciBiS3QTPh467dP5gyX37yzkSLzlprR7219gwAvaNmL86z_85I5icgOzxM5vXyXY2ipxy8qAexTI8AmwnA-CefeY4yt_oR5TWH9QproGJEo-DME-6Fxh5B_AaNLibKwc1TBBfI_qg1YfGHutw1lj_J6Q8In648czl9lFXNibIp3mpczr2lU5R45AmtyMmglOQjXvmz7FhsuD_iADIy4bNAOj-Qq6uKPbDI6xSY2mwB4C_tz0",
};

export const CMD: WireEnvelope = {
  rev: 1,
  kind: "cmd",
  n: SNAP.n,
  ct: SNAP.ct,
};

export const ACK: WireEnvelope = {
  rev: 1,
  kind: "ack",
  n: SNAP.n,
  ct: SNAP.ct,
};
