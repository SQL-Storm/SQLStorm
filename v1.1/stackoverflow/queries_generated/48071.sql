-- {"query": "48071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 317} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.AnswerCount > 5
),
RecentActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(ph.Id) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.OwnerDisplayName,
    ra.LastEditDate,
    ra.EditCount,
    (rp.Score * 1000) + ra.EditCount AS CompositeScore
FROM RankedPosts rp
LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId
WHERE rp.RowNum <= 1000
ORDER BY CompositeScore DESC, rp.CreationDate DESC
LIMIT 500;