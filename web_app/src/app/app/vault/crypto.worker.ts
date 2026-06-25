// crypto.worker.ts
// Background Web Worker implementing the W3C WebCrypto API for AES-GCM operations

export interface CryptoWorkerMessage {
  type: "ENCRYPT" | "DECRYPT";
  payload: {
    data: ArrayBuffer;
    keyString: string; // Master key derived string
    iv?: Uint8Array; // Required for decryption
  };
}

export interface CryptoWorkerResponse {
  type: "ENCRYPT_SUCCESS" | "DECRYPT_SUCCESS" | "ERROR";
  payload: {
    data?: ArrayBuffer;
    iv?: Uint8Array;
    error?: string;
  };
}

interface WorkerContext {
  postMessage(message: CryptoWorkerResponse, transfer: Transferable[]): void;
  postMessage(message: CryptoWorkerResponse): void;
}

const ctx = self as unknown as WorkerContext;

// Convert string key into a W3C CryptoKey object via SHA-256 derivation
async function importKey(keyString: string): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const rawKeyMaterial = encoder.encode(keyString);

  // Hash key material to guarantee 256-bit AES key size
  const keyHash = await self.crypto.subtle.digest("SHA-256", rawKeyMaterial);

  return await self.crypto.subtle.importKey(
    "raw",
    keyHash,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"]
  );
}

self.onmessage = async (event: MessageEvent<CryptoWorkerMessage>) => {
  const { type, payload } = event.data;
  
  try {
    const key = await importKey(payload.keyString);

    if (type === "ENCRYPT") {
      // Generate secure random 12-byte IV for AES-GCM
      const iv = self.crypto.getRandomValues(new Uint8Array(12));
      
      const ciphertext = await self.crypto.subtle.encrypt(
        {
          name: "AES-GCM",
          iv: iv,
        },
        key,
        payload.data
      );

      const response: CryptoWorkerResponse = {
        type: "ENCRYPT_SUCCESS",
        payload: {
          data: ciphertext,
          iv: iv,
        },
      };

      // Post back ciphertext buffer utilizing Transferable Objects to avoid memory copy
      ctx.postMessage(response, [ciphertext]);
      
    } else if (type === "DECRYPT") {
      if (!payload.iv) {
        throw new Error("Initialization Vector (IV) is missing for decryption.");
      }

      const plaintext = await self.crypto.subtle.decrypt(
        {
          name: "AES-GCM",
          iv: payload.iv as unknown as BufferSource,
        },
        key,
        payload.data
      );

      const response: CryptoWorkerResponse = {
        type: "DECRYPT_SUCCESS",
        payload: {
          data: plaintext,
        },
      };

      // Post back plaintext buffer utilizing Transferable Objects
      ctx.postMessage(response, [plaintext]);
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    const response: CryptoWorkerResponse = {
      type: "ERROR",
      payload: {
        error: errorMsg,
      },
    };
    ctx.postMessage(response);
  }
};
