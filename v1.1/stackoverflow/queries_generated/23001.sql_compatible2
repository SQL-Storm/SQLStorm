WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    WHERE u.Reputation > 1000 AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS QuestionRank,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 10000
      AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
),
CombinedStats AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.AvgPostScore,
        us.LastPostDate,
        us.ReputationRank,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BadgeNames, 'No Badges') AS BadgeNames,
        COALESCE(SUM(tq.ViewCount), 0) AS TotalQuestionViews,
        MAX(tq.QuestionRank) AS MaxQuestionRank
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON bs.UserId = us.UserId
    LEFT JOIN TopQuestions tq ON tq.OwnerUserId = us.UserId
    WHERE us.ReputationRank <= 100
    GROUP BY
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.AvgPostScore,
        us.LastPostDate,
        us.ReputationRank,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BadgeNames
    UNION
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        0 AS TotalPosts,
        NULL AS AvgPostScore,
        NULL AS LastPostDate,
        NULL AS ReputationRank,
        0 AS GoldBadges,
        0 AS SilverBadges,
        'Inactive' AS BadgeNames,
        0 AS TotalQuestionViews,
        NULL AS MaxQuestionRank
    FROM Users u
    WHERE u.Id NOT IN (SELECT UserId FROM UserStats)
      AND u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year')
      AND NOT EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = u.Id)
)
SELECT 
    cs.UserId,
    UPPER(cs.DisplayName) AS UpperName,
    cs.Reputation,
    cs.TotalPosts,
    ROUND(CAST(cs.AvgPostScore AS numeric), 2) AS RoundedAvgScore,
    cs.LastPostDate,
    cs.ReputationRank,
    (cs.GoldBadges + cs.SilverBadges) AS TotalBadges,
    cs.BadgeNames,
    cs.TotalQuestionViews,
    CASE 
        WHEN cs.MaxQuestionRank IS NULL THEN 'No Top Questions'
        WHEN cs.MaxQuestionRank = 1 THEN 'Top Questioner'
        ELSE 'Rank ' || CAST(cs.MaxQuestionRank AS varchar)
    END AS QuestionRankDescription,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = cs.UserId) 
       AND ph.PostHistoryTypeId = 10 AND (cs.LastPostDate IS NULL OR ph.CreationDate > cs.LastPostDate)) AS ClosedPostsAfterLast
FROM CombinedStats cs
WHERE cs.TotalQuestionViews > 0 OR (cs.GoldBadges + cs.SilverBadges) > 0
ORDER BY cs.Reputation DESC, cs.TotalPosts DESC;