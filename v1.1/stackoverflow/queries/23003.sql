WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
        STRING_AGG(COALESCE(p.Tags, ''), '; ') AS AllTags,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS ActivityRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE (p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL)  -- Questions and Answers
      AND (p.CreationDate > DATE '2020-01-01' OR p.CreationDate IS NULL)
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM Votes v
    WHERE v.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 YEAR')
    GROUP BY v.PostId
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) > 50
),
CombinedData AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.PostCount,
        ua.TotalScore,
        ua.AvgViewCount,
        ua.AllTags,
        ua.ActivityRank,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.LatestBadgeDate,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = ua.UserId AND c.Score > 5) AS HighScoreComments,
        COALESCE(
            (SELECT AVG(tp.NetVotes) 
             FROM TopVotedPosts tp 
             INNER JOIN Posts pp ON tp.PostId = pp.Id 
             WHERE pp.OwnerUserId = ua.UserId), 
            0
        ) AS AvgTopVotes
    FROM UserActivity ua
    FULL OUTER JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    WHERE (ua.Reputation > 1000 OR bs.GoldBadges >= 1)
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        0 AS PostCount,
        0 AS TotalScore,
        0 AS AvgViewCount,
        NULL AS AllTags,
        NULL AS ActivityRank,
        0 AS GoldBadges,
        0 AS SilverBadges,
        NULL AS LatestBadgeDate,
        0 AS HighScoreComments,
        0 AS AvgTopVotes
    FROM Users u
    WHERE u.Id NOT IN (SELECT UserId FROM UserActivity) 
      AND u.Id NOT IN (SELECT UserId FROM BadgeSummary)
      AND EXISTS (
        SELECT 1 FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
          AND ph.PostHistoryTypeId = 10  -- Post Closed
          AND ph.Comment LIKE '%duplicate%'
      )
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.PostCount,
    cd.TotalScore,
    cd.AvgViewCount,
    cd.AllTags,
    cd.ActivityRank,
    cd.GoldBadges,
    cd.SilverBadges,
    cd.LatestBadgeDate,
    cd.HighScoreComments,
    cd.AvgTopVotes,
    RANK() OVER (PARTITION BY cd.GoldBadges ORDER BY cd.TotalScore DESC) AS ScoreRankWithinGold,
    CASE 
        WHEN cd.AllTags IS NOT NULL AND cd.AllTags LIKE '%sql%' THEN 'SQL Expert'
        WHEN cd.AllTags IS NOT NULL AND cd.AllTags LIKE '%performance%' THEN 'Perf Guru'
        ELSE COALESCE(NULLIF(cd.DisplayName, ''), 'Unknown')
    END AS UserCategory,
    COALESCE(cd.AvgTopVotes * 1.5 + cd.HighScoreComments, 0) AS WeightedMetric
FROM CombinedData cd
WHERE COALESCE(cd.AvgTopVotes * 1.5 + cd.HighScoreComments, 0) > 100
GROUP BY
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.PostCount,
    cd.TotalScore,
    cd.AvgViewCount,
    cd.AllTags,
    cd.ActivityRank,
    cd.GoldBadges,
    cd.SilverBadges,
    cd.LatestBadgeDate,
    cd.HighScoreComments,
    cd.AvgTopVotes
ORDER BY cd.ActivityRank ASC, WeightedMetric DESC
LIMIT 100;