-- {"query": "45036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 492}
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostScoreRank,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation DIV 1000 ORDER BY p.ViewCount DESC) AS ViewCountRank
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 1000
),
PostInteractions AS (
    SELECT 
        rp.UserId,
        rp.Reputation,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(rp.Score) AS AvgPostScore
    FROM 
        RankedUserPosts rp
        LEFT JOIN Votes v ON rp.PostId = v.PostId
        LEFT JOIN Comments c ON rp.PostId = c.PostId
    WHERE 
        rp.PostScoreRank <= 3 
        AND rp.ViewCountRank <= 5
    GROUP BY 
        rp.UserId, rp.Reputation
)
SELECT 
    pi.UserId,
    pi.Reputation,
    pi.VoteCount,
    pi.CommentCount,
    pi.AvgPostScore,
    (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = pi.UserId) AS BadgeCount
FROM 
    PostInteractions pi
WHERE 
    pi.VoteCount > 10 
    AND pi.CommentCount > 5
ORDER BY 
    pi.Reputation DESC, 
    pi.VoteCount DESC
LIMIT 100;
