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
PostVoteCounts AS (
    SELECT 
        PostId, 
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Votes
    GROUP BY PostId
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
    LEFT JOIN PostVoteCounts v ON p.Id = v.PostId
),
MedianView AS (
    SELECT AVG(view_val) AS MedianViewCount
    FROM (
        SELECT ViewCount AS view_val,
               ROW_NUMBER() OVER (ORDER BY ViewCount) AS rn,
               COUNT(*) OVER () AS cnt
        FROM Posts
        WHERE ViewCount IS NOT NULL
    ) t
    WHERE rn IN (FLOOR((cnt+1)/2.0), CEIL((cnt+1)/2.0))
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
    mv.MedianViewCount
FROM UserBadgeCounts ubc
JOIN PostPerformance pp ON ubc.UserId = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = pp.PostId
)
JOIN Posts p ON pp.PostId = p.Id
LEFT JOIN Tags t ON (
    CASE 
      WHEN p.Tags IS NULL THEN NULL
      ELSE
        CASE
          WHEN POSITION('><' IN p.Tags) > 0 THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags)-2)
          ELSE SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2))
        END
    END
) = t.TagName
CROSS JOIN MedianView mv
WHERE 
    ubc.TotalBadges > 0 
    AND pp.PostTypeId IN (1, 2)
    AND pp.NetVotes > 0
    AND t.TagName IS NOT NULL
GROUP BY
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.BadgeRank,
    pp.PostId,
    pp.PostTypeId,
    pp.Score,
    pp.NetVotes,
    pp.ScoreRank,
    ubc.GoldBadges,
    ubc.SilverBadges,
    t.TagName,
    mv.MedianViewCount
ORDER BY 
    ubc.TotalBadges DESC, 
    pp.NetVotes DESC
LIMIT 100;