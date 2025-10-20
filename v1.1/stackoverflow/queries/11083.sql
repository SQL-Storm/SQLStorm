-- {"query": "11083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 559} 
WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(COALESCE(c.Score, 0)) AS HighestCommentScore
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
PostActivity AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.CreationDate) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.VoteCount,
    rp.UpVoteCount,
    rp.DownVoteCount,
    rp.HighestCommentScore,
    COALESCE(pa.EditCount, 0) AS EditCount,
    COALESCE(pa.LastEditDate, rp.CreationDate) AS LastEditDate,
    COALESCE(pa.ClosedCount, 0) AS ClosedCount,
    (rp.Score + rp.ViewCount + rp.VoteCount + COALESCE(pa.EditCount, 0) + COALESCE(rp.HighestCommentScore, 0)) AS ActivityScore
FROM 
    RecentPosts rp
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.PostId
ORDER BY 
    ActivityScore DESC
LIMIT 10;