-- {"query": "15051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 121420, "output_tokens": 35968} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        v.UpvoteCount,
        v.DownvoteCount,
        COALESCE(v.UpvoteCount, 0) - COALESCE(v.DownvoteCount, 0) AS NetVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.BadgeRank,
    pp.PostId,
    pp.PostTypeId,
    pp.Score,
    pp.NetVotes,
    pp.ScoreRank,
    CASE 
        WHEN ubc.GoldBadges > 5 AND pp.NetVotes > 10 THEN 'High Performer'
        WHEN ubc.SilverBadges > 3 AND pp.NetVotes > 5 THEN 'Emerging Contributor'
        ELSE 'Regular User'
    END AS UserCategory,
    t.TagName,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pp.ViewCount) OVER () AS MedianViewCount
FROM UserBadgeCounts ubc
JOIN PostPerformance pp ON ubc.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pp.PostId)
JOIN Posts p ON pp.PostId = p.Id
LEFT JOIN Tags t ON (
    SELECT (string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))[1]
) = t.TagName
WHERE 
    ubc.TotalBadges > 0 
    AND pp.PostTypeId IN (1, 2)
    AND pp.NetVotes > 0
    AND t.TagName IS NOT NULL
ORDER BY 
    ubc.TotalBadges DESC, 
    pp.NetVotes DESC
LIMIT 100;