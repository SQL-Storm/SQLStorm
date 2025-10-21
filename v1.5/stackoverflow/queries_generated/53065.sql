-- {"query": "53065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 452} 

WITH PostStats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT ph.Id) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseAttempts,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks,
        AVG(CASE WHEN a.PostTypeId = 2 THEN a.Score ELSE NULL END) AS AvgAnswerScore
    FROM 
        Posts p
    JOIN 
        Users u ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON v.PostId = p.Id
    LEFT JOIN 
        PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    LEFT JOIN 
        PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN 
        Posts a ON a.ParentId = p.Id
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
RankedStats AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY OwnerReputation ORDER BY (Upvotes - Downvotes) ASC, ViewCount DESC) AS ControversyRank
    FROM 
        PostStats
    WHERE 
        Upvotes > 50 
        AND Downvotes > 10 
        AND EditCount > 5 
        AND CommentCount > 10 
        AND OwnerReputation > 1000
)
SELECT 
    *
FROM 
    RankedStats
WHERE 
    ControversyRank <= 5
ORDER BY 
    OwnerReputation DESC, ControversyRank
LIMIT 100;
