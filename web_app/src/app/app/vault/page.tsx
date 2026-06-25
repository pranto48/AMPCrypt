"use client";

import React, { useState, useEffect, useRef } from "react";
import Navbar from "@/components/Navbar";
import { Lock, Unlock, FileUp, Shield, Cpu, RefreshCw, CheckCircle, AlertTriangle, Key } from "lucide-react";
import { CryptoWorkerMessage, CryptoWorkerResponse } from "./crypto.worker";

export default function VaultPage() {
  const [passphrase, setPassphrase] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [status, setStatus] = useState<"IDLE" | "PROCESSING" | "SUCCESS" | "ERROR">("IDLE");
  const [statusMessage, setStatusMessage] = useState("");
  
  // Encryption state holders
  const [encryptedData, setEncryptedData] = useState<ArrayBuffer | null>(null);
  const [iv, setIv] = useState<Uint8Array | null>(null);
  const [processingTime, setProcessingTime] = useState<number | null>(null);
  const [operationType, setOperationType] = useState<"ENCRYPT" | "DECRYPT" | null>(null);

  const workerRef = useRef<Worker | null>(null);

  // Instantiation of background worker using Next.js asset URL
  useEffect(() => {
    workerRef.current = new Worker(new URL("./crypto.worker.ts", import.meta.url));

    workerRef.current.onmessage = (event: MessageEvent<CryptoWorkerResponse>) => {
      const { type, payload } = event.data;
      const endTime = performance.now();

      if (type === "ENCRYPT_SUCCESS" && payload.data && payload.iv) {
        setEncryptedData(payload.data);
        setIv(payload.iv);
        setStatus("SUCCESS");
        setStatusMessage(`File encrypted successfully in offscreen worker thread.`);
        if (startTimeRef.current) setProcessingTime(endTime - startTimeRef.current);
      } else if (type === "DECRYPT_SUCCESS" && payload.data) {
        // Trigger download of decrypted file
        const blob = new Blob([payload.data]);
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = selectedFile ? `decrypted-${selectedFile.name}` : "decrypted-file";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        setStatus("SUCCESS");
        setStatusMessage("File decrypted successfully and download triggered!");
        if (startTimeRef.current) setProcessingTime(endTime - startTimeRef.current);
      } else if (type === "ERROR") {
        setStatus("ERROR");
        setStatusMessage(payload.error || "An error occurred inside the cryptographic worker.");
      }
    };

    return () => {
      if (workerRef.current) {
        workerRef.current.terminate();
      }
    };
  }, [selectedFile]);

  const startTimeRef = useRef<number | null>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      setSelectedFile(e.target.files[0]);
      setStatus("IDLE");
      setEncryptedData(null);
      setIv(null);
      setProcessingTime(null);
    }
  };

  const handleEncrypt = async () => {
    if (!selectedFile || !passphrase || !workerRef.current) return;

    setStatus("PROCESSING");
    setOperationType("ENCRYPT");
    setStatusMessage("Deriving key and encrypting block...");
    startTimeRef.current = performance.now();

    const fileReader = new FileReader();
    fileReader.onload = () => {
      const arrayBuffer = fileReader.result as ArrayBuffer;
      const message: CryptoWorkerMessage = {
        type: "ENCRYPT",
        payload: {
          data: arrayBuffer,
          keyString: passphrase,
        },
      };
      // Send arrayBuffer via transferable list to avoid deep copies
      workerRef.current?.postMessage(message, [arrayBuffer]);
    };
    fileReader.readAsArrayBuffer(selectedFile);
  };

  const handleDecrypt = () => {
    if (!encryptedData || !iv || !passphrase || !workerRef.current) return;

    setStatus("PROCESSING");
    setOperationType("DECRYPT");
    setStatusMessage("Re-assembling cipher block and decrypting...");
    startTimeRef.current = performance.now();

    // Copy arrayBuffer for transfer to worker
    const bufferCopy = encryptedData.slice(0);
    const message: CryptoWorkerMessage = {
      type: "DECRYPT",
      payload: {
        data: bufferCopy,
        keyString: passphrase,
        iv: iv,
      },
    };
    workerRef.current.postMessage(message, [bufferCopy]);
  };

  return (
    <div className="bg-[#0A0A0A] text-white min-h-screen relative font-sans">
      <Navbar />

      <main className="max-w-4xl mx-auto px-4 pt-32 pb-16 relative z-10">
        {/* Ambient Top Glow */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[500px] h-[300px] bg-[#00E5FF]/10 rounded-full filter blur-[100px] pointer-events-none" />

        <div className="text-center space-y-4 mb-12">
          <h1 className="text-4xl font-extrabold tracking-tight">
            Cryptographic <span className="text-[#00E5FF]">Client Vault</span>
          </h1>
          <p className="text-gray-400 max-w-xl mx-auto text-sm font-mono">
            Zero-knowledge client-side encryption. Keys and data never leave the browser. All heavy encryption operations execute in a separate worker thread.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Key and File Configuration Panel */}
          <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md">
            <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
              <Key className="w-5 h-5 text-[#00E5FF]" /> Configuration
            </h2>

            <div className="space-y-2">
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                Vault Passphrase
              </label>
              <input
                type="password"
                placeholder="Enter strong encryption key"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#00E5FF] transition-colors"
              />
            </div>

            <div className="space-y-2">
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                Select File to Secure
              </label>
              <div className="border border-dashed border-white/10 rounded-xl p-6 text-center hover:border-[#00E5FF]/50 transition-colors relative group">
                <input
                  type="file"
                  onChange={handleFileChange}
                  className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                />
                <FileUp className="w-8 h-8 text-gray-500 group-hover:text-[#00E5FF] transition-colors mx-auto mb-2" />
                <span className="text-sm font-medium text-gray-300 block">
                  {selectedFile ? selectedFile.name : "Choose or drop a file"}
                </span>
                {selectedFile && (
                  <span className="text-xs text-gray-500 font-mono block mt-1">
                    {(selectedFile.size / 1024).toFixed(2)} KB
                  </span>
                )}
              </div>
            </div>

            <button
              onClick={handleEncrypt}
              disabled={!selectedFile || !passphrase || status === "PROCESSING"}
              className="w-full py-3.5 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/10 hover:shadow-cyan-500/20 hover:bg-[#00E5FF]/90 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none transition-all flex items-center justify-center gap-2"
            >
              <Lock className="w-4 h-4" /> Encrypt File (AES-GCM)
            </button>
          </div>

          {/* Cryptographic Execution Console */}
          <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md flex flex-col">
            <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
              <Cpu className="w-5 h-5 text-[#00E5FF]" /> Worker Console
            </h2>

            <div className="flex-grow flex flex-col justify-center items-center p-6 bg-[#141414] rounded-xl border border-white/5 min-h-[220px]">
              {status === "IDLE" && (
                <div className="text-center space-y-2">
                  <Shield className="w-12 h-12 text-gray-600 mx-auto" />
                  <p className="text-sm text-gray-400">Awaiting configuration parameters...</p>
                </div>
              )}

              {status === "PROCESSING" && (
                <div className="text-center space-y-3">
                  <RefreshCw className="w-10 h-10 text-[#00E5FF] animate-spin mx-auto" />
                  <p className="text-sm font-semibold">{statusMessage}</p>
                  <p className="text-xs text-gray-500 font-mono">Running WebCrypto AES-GCM on worker thread</p>
                </div>
              )}

              {status === "SUCCESS" && (
                <div className="text-center space-y-3">
                  <CheckCircle className="w-12 h-12 text-emerald-500 mx-auto animate-bounce" />
                  <p className="text-sm font-semibold text-emerald-400">{statusMessage}</p>
                  {processingTime !== null && (
                    <div className="inline-block px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 rounded-full text-xs font-mono text-emerald-400">
                      Elapsed Time: {processingTime.toFixed(2)} ms
                    </div>
                  )}
                </div>
              )}

              {status === "ERROR" && (
                <div className="text-center space-y-2">
                  <AlertTriangle className="w-12 h-12 text-rose-500 mx-auto" />
                  <p className="text-sm font-semibold text-rose-400">{statusMessage}</p>
                </div>
              )}
            </div>

            {encryptedData && status === "SUCCESS" && operationType === "ENCRYPT" && (
              <div className="space-y-3 border-t border-white/5 pt-4">
                <div className="flex justify-between items-center text-xs text-gray-400 font-mono">
                  <span>Encrypted Payload:</span>
                  <span>{encryptedData.byteLength} bytes</span>
                </div>
                <button
                  onClick={handleDecrypt}
                  className="w-full py-3 bg-white/5 text-white font-semibold rounded-xl border border-white/10 hover:bg-white/10 active:scale-[0.98] transition-all flex items-center justify-center gap-2"
                >
                  <Unlock className="w-4 h-4 text-[#00E5FF]" /> Decrypt Payload
                </button>
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
