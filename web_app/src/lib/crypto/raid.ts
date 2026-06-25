// raid.ts
// Client-side RAID-5 chunk sharding and XOR parity calculation logic

export interface ShardPayload {
  index: number;
  data: ArrayBuffer;
  isParity: boolean;
}

export class VaultRaid {
  /**
   * Split a file chunk into N-1 data shards and calculate 1 XOR parity shard (RAID-5).
   * @param chunkData Original file chunk buffer (e.g. 32 KiB)
   * @param totalShards Total number of providers/shards (must be >= 3)
   */
  static shardChunk(chunkData: ArrayBuffer, totalShards: number): ShardPayload[] {
    if (totalShards < 3) {
      throw new Error("RAID-5 sharding requires at least 3 storage providers.");
    }

    const dataShardsCount = totalShards - 1;
    const originalLength = chunkData.byteLength;
    
    // Calculate size per shard (padded to be uniform)
    const shardSize = Math.ceil(originalLength / dataShardsCount);
    const paddedLength = shardSize * dataShardsCount;
    
    const paddedBuffer = new Uint8Array(paddedLength);
    paddedBuffer.set(new Uint8Array(chunkData));

    const shards: ShardPayload[] = [];
    const parityBuffer = new Uint8Array(shardSize);

    // Slice data shards and XOR them into the parity shard
    for (let i = 0; i < dataShardsCount; i++) {
      const start = i * shardSize;
      const shardData = paddedBuffer.slice(start, start + shardSize);
      
      shards.push({
        index: i,
        data: shardData.buffer as ArrayBuffer,
        isParity: false,
      });

      // Compute XOR for parity
      for (let j = 0; j < shardSize; j++) {
        parityBuffer[j] ^= shardData[j];
      }
    }

    // Add parity shard at the end (index = N-1)
    shards.push({
      index: totalShards - 1,
      data: parityBuffer.buffer as ArrayBuffer,
      isParity: true,
    });

    return shards;
  }

  /**
   * Reconstruct a missing shard from the remaining N-1 shards using XOR.
   * Works for both missing data shards and missing parity shards.
   * @param shards Array of N shards, where exactly one index is null (missing)
   * @param missingIndex Index of the missing shard to reconstruct
   * @param originalLength Original length of the unpadded chunk data to trim padding
   */
  static reconstructChunk(
    shards: (ArrayBuffer | null)[],
    missingIndex: number,
    originalLength: number
  ): ArrayBuffer {
    const totalShards = shards.length;
    if (totalShards < 3) {
      throw new Error("RAID-5 reconstruction requires at least 3 shards.");
    }

    // Find a valid shard to get the uniform shard size
    const sampleShard = shards.find((s) => s !== null);
    if (!sampleShard) {
      throw new Error("Insufficient shards available for reconstruction.");
    }
    const shardSize = sampleShard.byteLength;

    // Allocate buffer for the missing shard
    const reconstructedBuffer = new Uint8Array(shardSize);

    // XOR all available shards to rebuild the missing one
    for (let i = 0; i < totalShards; i++) {
      if (i === missingIndex) continue;
      
      const shard = shards[i];
      if (!shard) {
        throw new Error("Multiple shards are missing. RAID-5 can only recover from a single provider failure.");
      }

      const shardView = new Uint8Array(shard);
      for (let j = 0; j < shardSize; j++) {
        reconstructedBuffer[j] ^= shardView[j];
      }
    }

    // Temporarily replace the missing shard in the list for re-assembly
    const completedShards = [...shards];
    completedShards[missingIndex] = reconstructedBuffer.buffer as ArrayBuffer;

    // Re-assemble the original data by concatenating the N-1 data shards
    const dataShardsCount = totalShards - 1;
    const assembledBuffer = new Uint8Array(shardSize * dataShardsCount);

    for (let i = 0; i < dataShardsCount; i++) {
      const shard = completedShards[i];
      if (!shard) throw new Error("Missing data shard during re-assembly.");
      assembledBuffer.set(new Uint8Array(shard), i * shardSize);
    }

    // Trim any padding bytes to recover the exact original chunk length
    return assembledBuffer.slice(0, originalLength).buffer as ArrayBuffer;
  }
}
