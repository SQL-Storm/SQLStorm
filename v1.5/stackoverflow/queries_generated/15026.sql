-- {"query": "15026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 63045, "output_tokens": 18824} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
PostScoreAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM 
        Posts p
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ubc.BadgeRank,
    COALESCE(psa.PostId, -1) AS TopPost,
    psa.PostTypeId,
    psa.Score,
    psa.ScoreRank,
    psa.UpVotes,
    psa.DownVotes,
    CASE 
        WHEN psa.UpVotes > 0 THEN ROUND(psa.UpVotes * 100.0 / (psa.UpVotes + psa.DownVotes), 2)
        ELSE 0 
    END AS UpVotePercentage,
    COALESCE(
        (SELECT TOP 1 t.TagName 
         FROM Tags t 
         WHERE CHARINDEX('<' + t.TagName + '>', psa.Tags) > 0 
         ORDER BY t.Count DESC), 
        'Unknown'
    ) AS TopTag
FROM 
    UserBadgeCounts ubc
LEFT JOIN 
    PostScoreAnalysis psa ON ubc.UserId = (
        SELECT TOP 1 p.OwnerUserId 
        FROM Posts p 
        WHERE p.Id = psa.PostId
    )
WHERE 
    ubc.TotalBadges > 10 
    AND (psa.Score > 100 OR psa.Score IS NULL)
ORDER BY 
    ubc.BadgeRank, 
    psa.Score DESC NULLS LAST
LIMIT 100;