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
        WHEN psa.UpVotes > 0 THEN ROUND(CAST(psa.UpVotes AS numeric) * 100.0 / NULLIF(psa.UpVotes + psa.DownVotes, 0), 2)
        ELSE 0 
    END AS UpVotePercentage,
    COALESCE(
        (SELECT t.TagName
         FROM Tags t
         WHERE POSITION('<' || t.TagName || '>' IN COALESCE(psa.Tags, '')) > 0
         ORDER BY t.Count DESC
         LIMIT 1),
        'Unknown'
    ) AS TopTag
FROM 
    UserBadgeCounts ubc
LEFT JOIN 
    PostScoreAnalysis psa ON ubc.UserId = (
        SELECT p.OwnerUserId
        FROM Posts p
        WHERE p.Id = psa.PostId
        ORDER BY p.Id
        LIMIT 1
    )
WHERE 
    ubc.TotalBadges > 10 
    AND (psa.Score > 100 OR psa.Score IS NULL)
GROUP BY
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ubc.BadgeRank,
    psa.PostId,
    psa.PostTypeId,
    psa.Score,
    psa.ScoreRank,
    psa.UpVotes,
    psa.DownVotes,
    psa.Tags
ORDER BY 
    ubc.BadgeRank, 
    psa.Score DESC NULLS LAST
LIMIT 100;