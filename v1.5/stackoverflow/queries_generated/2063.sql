-- {"query": "2063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 400} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p 
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
HighScoreComments AS (
    SELECT 
        PostId, 
        MAX(Score) AS MaxCommentScore
    FROM 
        Comments
    GROUP BY 
        PostId
),
BadgeCounts AS (
    SELECT 
        UserId, 
        COUNT(CASE WHEN Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.OwnerName,
    rp.CommentCount,
    COALESCE(hc.MaxCommentScore, 0) AS MaxCommentScore,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges
FROM 
    RecentPosts rp
LEFT JOIN 
    HighScoreComments hc ON rp.Id = hc.PostId
LEFT JOIN 
    BadgeCounts bc ON rp.OwnerName = bc.UserId
WHERE 
    rp.Score > 100
ORDER BY 
    rp.Score DESC, rp.CreationDate DESC;
