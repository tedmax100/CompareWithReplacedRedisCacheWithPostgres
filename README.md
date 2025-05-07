PostgreSQL 取代 Redis 當 CacheServer？
---

# 起因
上次看後端版看到[這篇討論](https://www.facebook.com/groups/backendtw/posts/3600523966748120)，加上又在朋友臉書看到這影片後～[ replaced my Redis cache with Postgres... Here's what happened](https://youtu.be/KWaShWxJzxQ?si=TaK7969JMoCJdZhm)
懷疑自己這世界變了嘛，於是決定跑看看測試。

# 測試
## 插入資料場景

k6 測試結果
![](/images/insert_benchmark.bmp)

PostgreSQL 監控
![](/images/insert_pg_monitor.bmp)

Redis 監控
![](/images/insert_redis_monitor.bmp)

PostgreSQL table 大小
![](/images/pg_table_size.bmp)

## 查詢資料場景

k6 測試結果
![](/images/query_benchmark.bmp)

PostgreSQL 監控
![](/images/query_pg_monitor.bmp)

Redis 監控
![](/images/query_redis_monitor.bmp)

# 心得想法

1. **租用成本**
都以 AWS 美東為例，單一節點

RDS選用 db.t4g.small USD 0.032
一般用途 SSD (gp2) – 儲存 每月每 GB USD 0.115
每 GB 快照大小的費用： USD 0.010

MemoryDB db.t4g.small 2 1.37 最多 5 USD 0.0336
兩者幾乎不相上下，不便宜

2. **資源隔離**
Cache server 不可能與 database放同一台對吧，
雞蛋不會放同一個籃子裡面
所以要用要碼就是 2台pg (1cache+1db)
不然就是 1 redis + 1pg
不可能你用1pg 同時當cache又當db，那剛剛測試案例的場景已經告訴你了，連線數量跟請求工作都沒分攤掉。

3. **Cache 生命週期管理**
Cache server 有 `expiration`, `eviction` 機制
postgresql 要做就要用類似 `pg_cron` pluging，定期去掃scan table 去刪除
而 redis 內部自己有管理機制

4. **UNLOGGED Table**
they are `not crash-safe`

https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-UNLOGGED

5. **Data Page 利用率**
PostgreSQL data page 大小是 8kb，不管理面只有一筆或是多筆。大多情況下 8kb 的利用率很差的。

6. **MVCC 機制**
PostgreSQL 的 MVCC 機制雖然提供了事務一致性，但對於快取用途來說反而是負擔：
   - 每次更新資料都會建立新版本，而舊版本要等 vacuum 清理
   - 頻繁更新的快取資料會導致表膨脹，需要更頻繁的vacuum
   - 讀取時可能需要處理可見性檢查，增加額外開銷
   - Redis 單線程模型避免了這些複雜性，沒有這方面的開銷

1. **記憶體使用效率**
   - Redis 設計為完全記憶體資料庫，所有資料結構都針對記憶體操作優化
   - PostgreSQL 即使使用shared_buffers，其記憶體管理還是針對磁盤讀寫優化
   - Redis 支持數據壓縮、bitwise操作等特殊優化技術
   - PostgreSQL 在記憶體中還需維護索引、事務日誌等額外結構

2. **數據類型與操作**
   - Redis 原生支援多種特殊數據類型：Sets, Sorted Sets, Streams, HyperLogLog等
   - Redis提供了atomic計數器、發布訂閱、分佈式鎖等簡便實現
   - PostgreSQL需要用SQL和額外邏輯實現這些功能，開銷更大

3. **連線模型差異**
   - Redis 採用單線程事件驅動模型，特別適合處理大量簡單請求
   - PostgreSQL 為每個連線分配獨立thread，在高併發簡單查詢時效率較低
   - 測試圖表顯示，Redis的連線處理能力明顯優於PostgreSQL

4.  **分佈式場景考量**
    - Redis 提供叢集、哨兵等高可用機制，專為分佈式cache設計
    - Redis 支持一致性hash等sharding策略
    - PostgreSQL 雖有replication功能，但其分布式設計更適合數據儲存而非cache

5.  **總結比較**

| 特性 | PostgreSQL | Redis |
|------|------------|-------|
| 讀取速度 | 較慢 | 較快 |
| 寫入速度 | 較慢 | 較快 |
| 記憶體效率 | 較低 | 較高 |
| 資料持久化 | 原生支援 | 可選配置 |
| 事務支援 | 完整ACID | 有限支持 |
| 過期機制 | 需額外實現 | 內建支持 |
| 資源消耗 | 較高 | 較低 |
| 適用場景 | 複雜查詢、數據分析 | 高頻簡單操作、快取 |

基於以上分析和測試結果，**PostgreSQL作為主數據庫，Redis作為專用cache服務器**的傳統架構仍然是現階段較為合理的選擇。雖然在某些特定場景下（如開發環境、POC 架構）使用PostgreSQL作為緩存可能是可行的，但在營運環境和規模化應用中，專用cache解決方案的優勢仍然明顯。