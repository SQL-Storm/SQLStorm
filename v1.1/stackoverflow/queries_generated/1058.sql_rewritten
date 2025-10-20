-- {"query": "1058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 528} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
),
TopPosts AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.UpVotes,
        rp.DownVotes,
        rp.CommentCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.rn = 1
    ORDER BY 
        rp.Score DESC, rp.ViewCount DESC
    LIMIT 10
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        p.Title,
        ph.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM 
        PostHistory ph
    JOIN 
        Posts p ON ph.PostId = p.Id
    WHERE 
        ph.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY 
        ph.PostId, p.Title, ph.PostHistoryTypeId
)
SELECT 
    tp.Title, 
    tp.CreationDate, 
    tp.Score AS TotalScore, 
    tp.ViewCount,
    tp.UpVotes - tp.DownVotes AS NetVotes,
    COALESCE(p_h.ChangeCount, 0) AS HistoryChangeCount,
    CASE 
        WHEN tp.Score > 50 THEN 'High Score'
        WHEN tp.Score BETWEEN 10 AND 50 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory
FROM 
    TopPosts tp
LEFT JOIN 
    PostHistorySummary p_h ON tp.Id = p_h.PostId
ORDER BY 
    tp.Score DESC, tp.ViewCount DESC;