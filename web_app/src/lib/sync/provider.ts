// provider.ts
// Generic interface defining Cloud Storage Provider operations for encrypted chunk synchronization

export interface CloudStorageProvider {
  id: string;
  name: string;
  
  /**
   * Upload an encrypted chunk shard to the cloud provider.
   */
  uploadShard(vaultId: string, shardId: string, data: ArrayBuffer): Promise<void>;

  /**
   * Download a chunk shard from the cloud provider.
   */
  downloadShard(vaultId: string, shardId: string): Promise<ArrayBuffer>;

  /**
   * Delete a chunk shard from the cloud provider.
   */
  deleteShard(vaultId: string, shardId: string): Promise<void>;
}
