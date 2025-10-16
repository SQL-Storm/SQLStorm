-- {"query": "22086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1529} 
WITH UserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Score,
        p.OwnerUserId,
        p.Tags,
        COALESCE(v.Upvotes, 0) AS TotalUpvotes,
        COALESCE(v.Downvotes, 0) AS TotalDownvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreComments,
        CASE 
            WHEN p.Tags IS NULL THEN NULL
            ELSE ARRAY_AGG(DISTINCT TRIM(REGEXP_SPLIT_TO_TABLE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')))
        END AS TagArray
    FROM Posts p
    LEFT OUTER JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
)
SELECT
    ub.UserId,
    ub.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ps.Id AS PostId,
    ps.Score,
    ps.TotalUpvotes,
    ps.TotalDownvotes,
    ps.HighScoreComments,
    ARRAY_TO_STRING(ps.TagArray, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY ub.UserId ORDER BY ps.Score DESC) AS RankByScore
FROM UserBadges ub
LEFT OUTER JOIN PostStats ps ON ub.UserId = ps.OwnerUserId
WHERE EXISTS (
    SELECT 1 FROM Votes v2
    WHERE v2.PostId = ps.Id
    AND v2.UserId IS NOT NULL
    AND v2.CreationDate >= '2020-01-01'
    HAVING COUNT(DISTINCT v2.VoteTypeId) > 2
)
AND ps.Score > (
    SELECT AVG(p2.Score)
    FROM Posts p2
    WHERE p2.PostTypeId = 2
    AND p2.OwnerUserId = ub.UserId
)
AND ub.GoldBadges > 0
ORDER BY ub.TotalBadges DESC, ps.Score DESC
LIMIT 100
UNION ALL
SELECT
    NULL AS UserId,
    'Anonymous' AS DisplayName,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS PostId,
    NULL AS Score,
    NULL AS TotalUpvotes,
    NULL AS TotalDownvotes,
    NULL AS HighScoreComments,
    NULL AS Tags,
    NULL AS RankByScore
WHERE 1 = 0;  -- To make UNION compatible, but effectively empty, or adjust as needed for benchmarkingWITH UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(*) > 5
),
PostAggregates AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        CASE 
            WHEN p.Tags IS NULL OR LENGTH(p.Tags) < 3 THEN NULL
            ELSE UPPER(SUBSTRING(p.Tags FROM 3 FOR LENGTH(p.Tags) - 3))  -- Simplified tag extraction, assuming format
        END AS CleanedTags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score IS NOT NULL) AS CommentCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningVoteAvg
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2  -- Answers only
    GROUP BY p.OwnerUserId, p.Id, p.Score, p.CreationDate, p.Tags
),
CombinedStats AS (
    SELECT 
        ubs.UserId,
        ubs.DisplayName,
        ubs.UserRank,
        pa.PostId,
        pa.Score,
        pa.CleanedTags,
        pa.CommentCount,
        pa.TotalBounties,
        pa.RunningVoteAvg,
        CASE WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'High' ELSE 'Low' END AS ScoreCategory,
        RANK() OVER (PARTITION BY ubs.UserId ORDER BY pa.Score DESC) AS PostRankWithinUser
    FROM UserBadgeSummary ubs
    LEFT OUTER JOIN PostAggregates pa ON ubs.UserId = pa.OwnerUserId
    WHERE pa.Score IS NOT NULL OR pa.Score IS NULL  -- Include posts even if null, but with NULL logic
),
FinalRanking AS (
    SELECT *,
        DENSE_RANK() OVER (ORDER BY TotalBounties DESC, CommentCount DESC) AS BountyRank
    FROM CombinedStats
    WHERE EXISTS (
        SELECT 1 FROM PostHistory ph 
        WHERE ph.PostId = CombinedStats.PostId 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)  -- Edits and initial
        HAVING COUNT(*) > 10
    )
    AND (CleanedTags LIKE '%SQL%' OR CleanedTags IS NULL)
)
SELECT * FROM FinalRanking
WHERE UserRank <= 1000
AND PostRankWithinUser <= 3
ORDER BY UserRank, PostRankWithinUser
UNION
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE 1 = 1;  -- Dummy row for set operator compatibility, can be filtered in benchmarking