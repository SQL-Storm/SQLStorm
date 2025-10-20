WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(p.Id) > 10 AND SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) > 5
),
BadgeStats AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames,
           MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LatestGoldBadge
    FROM Badges b
    WHERE (b.TagBased = TRUE) OR (b.Class <= 2)
    GROUP BY b.UserId
),
PostAnalytics AS (
    SELECT p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.AnswerCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 1) AS HighScoreComments,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankPerUser,
           COALESCE(NULLIF(p.AnswerCount, 0), (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1)) AS AdjustedAnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags LIKE '%sql%'
      AND EXISTS (
          SELECT 1 FROM Votes v
          WHERE v.PostId = p.Id
            AND v.VoteTypeId = 2
            AND v.CreationDate > p.CreationDate + INTERVAL '1 day'
      )
),
MergedData AS (
    SELECT tu.Id, tu.Reputation, tu.DisplayName, tu.UserRank, tu.AvgQuestionScore,
           bs.BadgeCount, bs.BadgeNames, bs.LatestGoldBadge,
           pa.Title, pa.Tags, pa.Score, pa.ViewCount, pa.HighScoreComments, pa.PostRankPerUser, pa.AdjustedAnswerCount
    FROM TopUsers tu
    LEFT JOIN BadgeStats bs ON tu.Id = bs.UserId
    FULL OUTER JOIN PostAnalytics pa ON tu.Id = pa.OwnerUserId
    WHERE tu.UserRank <= 100 OR pa.PostRankPerUser = 1

    UNION

    SELECT NULL AS Id, 0 AS Reputation, 'Anonymous' AS DisplayName, 0 AS UserRank, 0 AS AvgQuestionScore,
           0 AS BadgeCount, '' AS BadgeNames, NULL AS LatestGoldBadge,
           p.Title, p.Tags, p.Score, p.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS HighScoreComments, 1 AS PostRankPerUser,
           COALESCE(p.AnswerCount, 0) AS AdjustedAnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NULL AND p.PostTypeId = 1
      AND NOT EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10)
)
SELECT md.Id, md.Reputation, md.DisplayName, md.UserRank, md.AvgQuestionScore,
       md.BadgeCount, md.BadgeNames, md.LatestGoldBadge,
       md.Title, md.Tags, md.Score, md.ViewCount, md.HighScoreComments, md.PostRankPerUser, md.AdjustedAnswerCount,
       (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = md.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
       CASE
           WHEN md.BadgeCount > 50 THEN 'Badge Master'
           WHEN md.BadgeCount BETWEEN 20 AND 50 THEN 'Badge Enthusiast'
           ELSE 'Badge Novice'
       END AS BadgeLevel,
       UPPER(SUBSTRING(md.Tags FROM 1 FOR (POSITION('>' IN md.Tags) - 1))) AS FirstTag,
       md.Score * md.ViewCount / NULLIF(md.AdjustedAnswerCount + 1, 0) AS EngagementScore
FROM MergedData md
WHERE (md.Reputation > 1000) OR (md.ViewCount > 10000)
ORDER BY md.UserRank ASC, EngagementScore DESC
LIMIT 1000;