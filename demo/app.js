import { ethers } from "https://esm.sh/ethers@6.13.4";

const cfg = () => window.DEMO_CONFIG || {};

function cadAddr(hex) {
  const h = hex.replace(/^0x/i, "");
  return "0x" + h.toLowerCase();
}

function b64Utf8(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

/** Unwrap JSON-CDC from Flow Access REST into plain JS structures. */
function simplify(v) {
  if (v == null) return v;
  if (typeof v !== "object") return v;
  if (!("type" in v) || !("value" in v)) return v;
  const { type, value } = v;
  if (type === "Array" || /^\[.*\]$/.test(type || "")) {
    return (value ?? []).map(simplify);
  }
  if (type === "Dictionary") {
    const out = {};
    for (const pair of value ?? []) {
      const k = simplify(pair.key);
      out[String(k)] = simplify(pair.value);
    }
    return out;
  }
  if (type === "Optional") {
    return value == null ? null : simplify(value);
  }
  if (type === "Void") return null;
  const prim = new Set([
    "String",
    "Bool",
    "Address",
    "UFix64",
    "Fix64",
    "UInt64",
    "UInt32",
    "UInt8",
    "UInt256",
    "UInt",
    "Int64",
    "Int32",
    "Int8",
    "Int",
  ]);
  if (prim.has(type)) return value;
  if (type === "Struct" || (type && type.includes(".") && value && value.fields)) {
    const val = value;
    if (val && Array.isArray(val.fields)) {
      const o = { __type: val.id || type };
      for (const f of val.fields) {
        o[f.name] = simplify(f.value);
      }
      return o;
    }
    if (Array.isArray(val)) {
      const o = { __type: type };
      for (const f of val) {
        o[f.name] = simplify(f.value);
      }
      return o;
    }
  }
  return value;
}

async function runCadenceScript(scriptCadence, jsonArgs = []) {
  const c = cfg();
  const rest = (c.flowAccessRest || "").replace(/\/$/, "");
  const url = `${rest}/v1/scripts?block_height=sealed`;
  const body = {
    script: b64Utf8(scriptCadence),
    arguments: jsonArgs.map((a) => b64Utf8(JSON.stringify(a))),
  };
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(text || res.statusText);
  const outer = JSON.parse(text);
  const innerText = new TextDecoder().decode(
    Uint8Array.from(atob(outer), (ch) => ch.charCodeAt(0)),
  );
  const inner = JSON.parse(innerText);
  return simplify(inner);
}

function scriptTvl(deployer) {
  const d = cadAddr(deployer);
  return `
import LiquidStaking from ${d}
import stFlowToken from ${d}

access(all) fun main(): [UFix64; 3] {
    return [
        LiquidStaking.totalFlowStaked,
        stFlowToken.totalSupply,
        LiquidStaking.protocolFeePercent
    ]
}
`.trim();
}

function scriptPrice(deployer) {
  const d = cadAddr(deployer);
  return `
import LiquidStaking from ${d}

access(all) fun main(): [UFix64; 2] {
    return [
        LiquidStaking.flowPerStFlow(),
        LiquidStaking.stFlowPerFlow()
    ]
}
`.trim();
}

function scriptDelegator(deployer, idTable) {
  const d = cadAddr(deployer);
  const t = cadAddr(idTable);
  return `
import FlowIDTableStaking from ${t}
import LiquidStaking from ${d}

access(all) fun main(): FlowIDTableStaking.DelegatorInfo {
    return LiquidStaking.getDelegatorInfo()
}
`.trim();
}

const VAULT_ABI = [
  "function owner() view returns (address)",
  "function ST_FLOW_ADDRESS() view returns (address)",
  "function stakeRequestCount() view returns (uint256)",
  "function getRate() view returns (uint256)",
  "function getConfig() view returns (tuple(uint256 minStakeAmount,bool isStakingPaused,bool isUnstakingPaused,uint256 protocolFee))",
  "function stakeRequests(uint256) view returns (tuple(uint8 status,address user,uint256 amount,uint256 flowWei))",
  "function requestStake() payable returns (uint256)",
];

const ERC20_ABI = ["function balanceOf(address) view returns (uint256)"];

function requestStatusLabel(n) {
  const x = Number(n);
  if (x === 0) return "NONE";
  if (x === 1) return "PENDING";
  if (x === 2) return "FULFILLED";
  return String(n);
}

function setStatus(t) {
  const el = document.getElementById("status");
  if (el) el.textContent = t || "";
}

function showErr(id, msg) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = "";
  const s = document.createElement("span");
  s.className = "err";
  s.textContent = msg;
  el.appendChild(s);
}

function fmtObj(o) {
  return JSON.stringify(o, (_k, v) => (typeof v === "bigint" ? v.toString() : v), 2);
}

async function refreshReads() {
  const c = cfg();
  setStatus("Loading…");

  const deployer = c.cadenceDeployer;
  const idTable = c.flowIDTableStaking;
  const vaultAddr = c.lspVault;
  const stAddr = c.bridgedStFlow;

  const addrDl = document.getElementById("addr-list");
  const epDl = document.getElementById("endpoint-list");
  if (addrDl) {
    addrDl.innerHTML = `
      <dt>cadenceDeployer</dt><dd>${deployer || "—"}</dd>
      <dt>flowIDTableStaking</dt><dd>${idTable || "—"}</dd>
      <dt>lspVault</dt><dd>${vaultAddr || "—"}</dd>
      <dt>bridgedStFlow</dt><dd>${stAddr || "—"}</dd>
      <dt>evmBalanceOfAddress</dt><dd>${c.evmBalanceOfAddress || "(unset)"}</dd>
    `;
  }
  if (epDl) {
    epDl.innerHTML = `
      <dt>Flow REST</dt><dd>${c.flowAccessRest || "—"}</dd>
      <dt>EVM RPC</dt><dd>${c.evmRpc || "—"}</dd>
      <dt>chainId</dt><dd>${c.evmChainId ?? "—"}</dd>
    `;
  }

  const cadenceOk = deployer && deployer !== "0x0000000000000000";
  const evmVaultOk =
    vaultAddr && vaultAddr !== "0x0000000000000000000000000000000000000000";
  const evmTokenOk =
    stAddr && stAddr !== "0x0000000000000000000000000000000000000000";

  if (!cadenceOk) {
    document.getElementById("out-tvl").textContent = "Set cadenceDeployer in config.";
    document.getElementById("out-price").textContent = "—";
    document.getElementById("out-delegator").textContent = "—";
  } else {
    try {
      const tvl = await runCadenceScript(scriptTvl(deployer));
      document.getElementById("out-tvl").textContent = fmtObj({
        totalFlowStaked: tvl?.[0],
        stFlowTotalSupply: tvl?.[1],
        protocolFeePercent: tvl?.[2],
      });
    } catch (e) {
      document.getElementById("out-tvl").textContent = String(e.message || e);
    }

    try {
      const price = await runCadenceScript(scriptPrice(deployer));
      document.getElementById("out-price").textContent = fmtObj({
        flowPerStFlow: price?.[0],
        stFlowPerFlow: price?.[1],
      });
    } catch (e) {
      document.getElementById("out-price").textContent = String(e.message || e);
    }

    try {
      const del = await runCadenceScript(scriptDelegator(deployer, idTable));
      document.getElementById("out-delegator").textContent = fmtObj(del);
    } catch (e) {
      document.getElementById("out-delegator").textContent = String(e.message || e);
    }
  }

  if (!evmVaultOk) {
    document.getElementById("out-evm-meta").textContent = "Set lspVault in config.";
    document.getElementById("out-evm-config").textContent = "—";
    document.getElementById("out-evm-balance").textContent = "—";
    document.getElementById("out-stake-requests").textContent = "—";
    const t = new Date().toLocaleTimeString();
    setStatus(
      (!cadenceOk && !evmVaultOk
        ? "Configure cadenceDeployer and lspVault."
        : !cadenceOk
          ? "Cadence reads skipped (deployer not set)."
          : "EVM reads skipped (set lspVault).") + ` ${t}`,
    );
    return;
  }

  try {
    const provider = new ethers.JsonRpcProvider(c.evmRpc, c.evmChainId, { staticNetwork: true });
    const vault = new ethers.Contract(vaultAddr, VAULT_ABI, provider);
    const [owner, stOnVault, rate, count] = await Promise.all([
      vault.owner(),
      vault.ST_FLOW_ADDRESS(),
      vault.getRate(),
      vault.stakeRequestCount(),
    ]);
    const conf = await vault.getConfig();
    document.getElementById("out-evm-meta").textContent = fmtObj({
      owner,
      ST_FLOW_ADDRESS: stOnVault,
      getRate: rate.toString(),
      stakeRequestCount: count.toString(),
    });
    document.getElementById("out-evm-config").textContent = fmtObj({
      minStakeAmount: conf.minStakeAmount.toString(),
      isStakingPaused: conf.isStakingPaused,
      isUnstakingPaused: conf.isUnstakingPaused,
      protocolFee: conf.protocolFee.toString(),
    });

    const balAddr = (c.evmBalanceOfAddress || "").trim();
    if (!evmTokenOk) {
      document.getElementById("out-evm-balance").textContent =
        "Set bridgedStFlow in config to query ERC-20 balance.";
    } else if (balAddr && ethers.isAddress(balAddr)) {
      const tok = new ethers.Contract(stAddr, ERC20_ABI, provider);
      const b = await tok.balanceOf(balAddr);
      document.getElementById("out-evm-balance").textContent = fmtObj({
        account: balAddr,
        bridgedStFlowBalance: b.toString(),
      });
    } else {
      document.getElementById("out-evm-balance").textContent =
        "Set evmBalanceOfAddress in config to query balanceOf.";
    }

    const n = Number(count);
    const lines = [];
    const lo = Math.max(1, n - 12);
    for (let i = n - 1; i >= lo; i--) {
      const r = await vault.stakeRequests(i);
      lines.push({
        id: i,
        status: requestStatusLabel(r.status),
        user: r.user,
        stFlowAmount: r.amount.toString(),
        flowWei: r.flowWei.toString(),
      });
    }
    document.getElementById("out-stake-requests").textContent = fmtObj(lines.reverse());
  } catch (e) {
    document.getElementById("out-evm-meta").textContent = String(e.message || e);
    document.getElementById("out-evm-config").textContent = "—";
    document.getElementById("out-evm-balance").textContent = "—";
    document.getElementById("out-stake-requests").textContent = "—";
  }

  setStatus("Updated " + new Date().toLocaleTimeString());
}

function buildKeeperArgsJson(stakeRequestId, flowWei, stflowAmount, vaultIdentifier) {
  const c = cfg();
  return [
    { type: "String", value: c.lspVault },
    { type: "String", value: c.bridgedStFlow },
    { type: "UInt256", value: String(stakeRequestId) },
    { type: "UInt", value: String(flowWei) },
    { type: "String", value: vaultIdentifier },
    { type: "UInt256", value: String(stflowAmount) },
  ];
}

async function buildKeeperCommand() {
  const c = cfg();
  const id = document.getElementById("keeper-id")?.value?.trim() || "1";
  const vid = (c.vaultIdentifier || "").trim();
  const ta = document.getElementById("keeper-cmd");
  if (!vid) {
    ta.value =
      "Set vaultIdentifier in config (output of stflow_vault_type_identifier.cdc) before generating this command.";
    return;
  }
  try {
    const provider = new ethers.JsonRpcProvider(c.evmRpc, c.evmChainId, { staticNetwork: true });
    const vault = new ethers.Contract(c.lspVault, VAULT_ABI, provider);
    const r = await vault.stakeRequests(id);
    if (r.flowWei === 0n) {
      ta.value = "No pending native lock for this id (flowWei is 0). Pick another stake request id.";
      return;
    }
    const args = buildKeeperArgsJson(id, r.flowWei.toString(), r.amount.toString(), vid);
    const json = JSON.stringify(args);
    const path = c.keeperCdcPath || "cadence/transactions/keeper/fulfill_evm_stake_bundle.cdc";
    const nf = c.networkFlag || "testnet";
    const signer = c.flowSigner || "testnet-acc";
    ta.value = `flow transactions send ${path} \\
  --args-json '${json.replace(/'/g, "'\\''")}' \\
  -n ${nf} --signer ${signer} -y --compute-limit 9999`;
  } catch (e) {
    ta.value = String(e.message || e);
  }
}

async function sendEvmStake() {
  const c = cfg();
  const msg = document.getElementById("evm-stake-msg");
  msg.innerHTML = "";
  const flowStr = document.getElementById("stake-flow")?.value?.trim() || "0";
  const pk = document.getElementById("evm-pk")?.value?.trim() || "";
  if (!pk) {
    showErr("evm-stake-msg", "Private key required.");
    return;
  }
  let wallet;
  try {
    wallet = new ethers.Wallet(pk.startsWith("0x") ? pk : "0x" + pk);
  } catch (e) {
    showErr("evm-stake-msg", "Invalid key: " + (e.message || e));
    return;
  }
  try {
    const provider = new ethers.JsonRpcProvider(c.evmRpc, c.evmChainId, { staticNetwork: true });
    const w = wallet.connect(provider);
    const vault = new ethers.Contract(c.lspVault, VAULT_ABI, w);
    const value = ethers.parseEther(flowStr);
    const tx = await vault.requestStake({ value });
    msg.innerHTML = `<div class="ok">Submitted: ${tx.hash}</div>`;
    await tx.wait();
    msg.innerHTML += `<div class="ok">Confirmed in block.</div>`;
    await refreshReads();
  } catch (e) {
    showErr("evm-stake-msg", String(e.shortMessage || e.message || e));
  }
}

document.getElementById("btn-refresh")?.addEventListener("click", () => refreshReads());
document.getElementById("btn-keeper-cmd")?.addEventListener("click", () => buildKeeperCommand());
document.getElementById("btn-evm-stake")?.addEventListener("click", () => sendEvmStake());

refreshReads();
