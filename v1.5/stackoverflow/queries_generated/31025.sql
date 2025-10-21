-- {"query": "31025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 446} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.CreationDate, 
        p.OwnerUserId, 
        u.DisplayName AS OwnerDisplayName, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 10
),
PostDetails AS (
    SELECT 
        rp.PostId, 
        rp.Title, 
        rp.Score, 
        rp.ViewCount, 
        rp.CreationDate, 
        rp.OwnerDisplayName, 
        COALESCE(COUNT(c.Id), 0) AS CommentCount, 
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM RankedPosts rp
    LEFT JOIN Comments c ON rp.PostId = c.PostId
    LEFT JOIN Votes v ON rp.PostId = v.PostId AND v.VoteTypeId IN (8, 9)  -- BountyStart and BountyClose
    WHERE rp.Rank <= 5
    GROUP BY rp.PostId, rp.Title, rp.Score, rp.ViewCount, rp.CreationDate, rp.OwnerDisplayName
),
TopPosts AS (
    SELECT 
        pd.*, 
        ROW_NUMBER() OVER (ORDER BY pd.Score DESC, pd.ViewCount DESC) AS OverallRank
    FROM PostDetails pd
)
SELECT 
    tp.PostId, 
    tp.Title, 
    tp.Score, 
    tp.ViewCount, 
    tp.CreationDate, 
    tp.OwnerDisplayName, 
    tp.CommentCount, 
    tp.TotalBounty,
    tp.OverallRank,
    pt.Name AS PostTypeName
FROM TopPosts tp
JOIN PostTypes pt ON pt.Id = (SELECT PostTypeId FROM Posts WHERE Id = tp.PostId)
WHERE tp.OverallRank <= 10
ORDER BY tp.OverallRank;
