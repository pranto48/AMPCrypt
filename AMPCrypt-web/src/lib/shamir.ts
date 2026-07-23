// Shamir's Secret Sharing (SSS) implementation in GF(256)
// Using generator 3 log/exp tables and Horner's method for polynomial evaluation

const logTable = new Uint8Array(256);
const expTable = new Uint8Array(256);

// Initialize GF(256) tables
let x = 1;
for (let i = 0; i < 255; i++) {
  expTable[i] = x;
  logTable[x] = i;
  x = (x << 1) ^ (x & 0x80 ? 0x11d : 0); // Primitive polynomial x^8 + x^4 + x^3 + x^2 + 1
}
expTable[255] = expTable[0];

function gfAdd(a: number, b: number): number {
  return a ^ b;
}

function gfMul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return expTable[(logTable[a] + logTable[b]) % 255];
}

function gfDiv(a: number, b: number): number {
  if (b === 0) throw new Error("Division by zero in GF(256)");
  if (a === 0) return 0;
  return expTable[(logTable[a] - logTable[b] + 255) % 255];
}

/**
 * Splits a secret passphrase into N shares, requiring at least T shares to reconstruct.
 */
export function splitSecret(secretStr: string, n: number, t: number): string[] {
  if (t > n) throw new Error("Threshold cannot exceed the total number of shares.");
  if (t < 2) throw new Error("Threshold must be at least 2.");

  const encoder = new TextEncoder();
  const secret = encoder.encode(secretStr);
  const shares: Uint8Array[] = Array.from({ length: n }, () => new Uint8Array(secret.length));

  for (let i = 0; i < secret.length; i++) {
    const s = secret[i];
    
    // Generate coefficients for polynomial of degree t-1
    const coeff = new Uint8Array(t);
    coeff[0] = s;
    for (let j = 1; j < t; j++) {
      coeff[j] = Math.floor(Math.random() * 256);
    }

    // Evaluate polynomial P(x) at x = 1..n using Horner's method
    for (let xVal = 1; xVal <= n; xVal++) {
      let y = coeff[t - 1];
      for (let j = t - 2; j >= 0; j--) {
        y = gfAdd(gfMul(y, xVal), coeff[j]);
      }
      shares[xVal - 1][i] = y;
    }
  }

  // Format shares as 'x-hexString'
  return shares.map((s, idx) => {
    const xVal = idx + 1;
    const hex = Array.from(s)
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");
    return `${xVal}-${hex}`;
  });
}

/**
 * Recombines a set of shares to reconstruct the secret passphrase.
 */
export function recombineShares(sharesStr: string[]): string {
  if (sharesStr.length === 0) return "";

  const parsedShares = sharesStr.map(s => {
    const parts = s.trim().split("-");
    if (parts.length !== 2) {
      throw new Error("Invalid share format. Expected format: 'index-hexString' (e.g. '1-abcdef')");
    }
    const xVal = parseInt(parts[0], 10);
    const hex = parts[1];
    
    const bytesMatch = hex.match(/.{1,2}/g);
    if (!bytesMatch) {
      throw new Error("Invalid hex string in share data.");
    }
    const bytes = new Uint8Array(bytesMatch.map(byte => parseInt(byte, 16)));
    return { x: xVal, bytes };
  });

  const secretLength = parsedShares[0].bytes.length;
  const secret = new Uint8Array(secretLength);

  for (let k = 0; k < secretLength; k++) {
    let secretByte = 0;
    
    // Lagrange interpolation at x = 0
    for (let i = 0; i < parsedShares.length; i++) {
      const xi = parsedShares[i].x;
      const yi = parsedShares[i].bytes[k];

      let li = 1;
      for (let j = 0; j < parsedShares.length; j++) {
        if (i === j) continue;
        const xj = parsedShares[j].x;
        const num = xj;
        const denom = gfAdd(xj, xi); // Subtraction is XOR in GF(256)
        li = gfMul(li, gfDiv(num, denom));
      }
      secretByte = gfAdd(secretByte, gfMul(yi, li));
    }
    secret[k] = secretByte;
  }

  const decoder = new TextDecoder();
  return decoder.decode(secret);
}
