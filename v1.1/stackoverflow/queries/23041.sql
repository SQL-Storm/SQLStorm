-- {"query": "23041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1135} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        COALESCE(p.AcceptedAnswerId, NULL) AS AcceptedAnswer
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags LIKE '%sql%'
),
PostHistoryAnalysis AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount
    FROM PostHistory ph
    GROUP BY ph.PostId
    HAVING COUNT(*) > 5
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.ReputationRank,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.BadgeNames, 'No Badges') AS BadgeNames,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    ROUND(us.AvgScore, 2) AS AvgScore,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount,
    tq.Score,
    tq.PositiveComments,
    CASE 
        WHEN tq.PreviousScore IS NULL THEN 'First Post'
        WHEN tq.Score > tq.PreviousScore THEN 'Improved'
        ELSE 'Declined'
    END AS ScoreTrend,
    pha.LastEditDate,
    pha.UniqueEditors,
    pha.EditCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 2) - (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 3) AS NetUpvotes
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
INNER JOIN TopQuestions tq ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = tq.PostId)
LEFT JOIN PostHistoryAnalysis pha ON tq.PostId = pha.PostId
LEFT OUTER JOIN PostLinks pl ON tq.PostId = pl.PostId AND pl.LinkTypeId = 3
WHERE us.ReputationRank <= 100
  AND (tq.AcceptedAnswer IS NOT NULL OR us.TotalPosts > 10)
  AND EXISTS (SELECT 1 FROM Tags t WHERE t.ExcerptPostId = tq.PostId OR t.WikiPostId = tq.PostId)
UNION
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(us.Reputation) AS Reputation,
    NULL AS ReputationRank,
    SUM(COALESCE(bs.TotalBadges, 0)) AS TotalBadges,
    SUM(COALESCE(bs.GoldBadges, 0)) AS GoldBadges,
    NULL AS BadgeNames,
    SUM(us.TotalPosts) AS TotalPosts,
    SUM(us.Questions) AS Questions,
    SUM(us.Answers) AS Answers,
    AVG(us.AvgScore) AS AvgScore,
    NULL AS TopQuestionTitle,
    SUM(tq.ViewCount) AS ViewCount,
    AVG(tq.Score) AS Score,
    SUM(tq.PositiveComments) AS PositiveComments,
    NULL AS ScoreTrend,
    NULL AS LastEditDate,
    AVG(pha.UniqueEditors) AS UniqueEditors,
    SUM(pha.EditCount) AS EditCount,
    NULL AS NetUpvotes
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
INNER JOIN TopQuestions tq ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = tq.PostId)
LEFT JOIN PostHistoryAnalysis pha ON tq.PostId = pha.PostId
WHERE us.ReputationRank <= 100
ORDER BY ReputationRank;