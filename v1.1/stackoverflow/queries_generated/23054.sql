-- {"query": "23054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1120} 

WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(b.Id) > 0
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS QuestionRank,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS PrevViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1  -- Questions
      AND p.ViewCount IS NOT NULL
      AND p.Title LIKE '%SQL%'  -- String expression
),
UserPostStats AS (
    SELECT 
        ubc.UserId,
        ubc.Reputation,
        ubc.DisplayName,
        ubc.GoldBadges,
        AVG(COALESCE(p.Score, 0)) AS AvgAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(tq.ViewCount) AS MaxQuestionViews,
        COALESCE(AVG(NULLIF(tq.PrevViewCount, tq.ViewCount)), 0) AS AvgViewDiff  -- NULL logic and calculation
    FROM UserBadgeCounts ubc
    LEFT OUTER JOIN Posts p ON ubc.UserId = p.OwnerUserId
    LEFT OUTER JOIN TopQuestions tq ON ubc.UserId = tq.OwnerUserId AND tq.QuestionRank = 1
    GROUP BY ubc.UserId, ubc.Reputation, ubc.DisplayName, ubc.GoldBadges
),
RecentEdits AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
      AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
),
CorrelatedSubqueryStats AS (
    SELECT 
        ups.UserId,
        ups.Reputation,
        ups.DisplayName,
        ups.GoldBadges,
        ups.AvgAnswerScore,
        ups.AnswerCount,
        ups.MaxQuestionViews,
        ups.AvgViewDiff,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ups.UserId AND c.Score > 5) AS HighScoreComments,  -- Correlated subquery
        COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ups.UserId) AND v.VoteTypeId = 9), 0) AS AvgBountyClosed  -- Nested subquery
    FROM UserPostStats ups
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.GoldBadges,
    cs.AvgAnswerScore,
    cs.AnswerCount,
    cs.MaxQuestionViews,
    cs.AvgViewDiff,
    cs.HighScoreComments,
    cs.AvgBountyClosed,
    re.EditCount,
    RANK() OVER (ORDER BY cs.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (PARTITION BY cs.GoldBadges ORDER BY cs.AvgAnswerScore DESC) AS ScoreRankPerGold
FROM CorrelatedSubqueryStats cs
LEFT OUTER JOIN RecentEdits re ON cs.UserId = re.UserId
WHERE cs.Reputation > 1000
  AND (cs.MaxQuestionViews > 10000 OR cs.AnswerCount > 50)
  AND EXISTS (SELECT 1 FROM Tags t WHERE t.Count > 1000 AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = cs.UserId AND p2.Tags LIKE '%' || t.TagName || '%'))  -- Complicated predicate with subquery and string expression

UNION ALL

SELECT 
    NULL AS UserId,
    'Aggregate' AS DisplayName,
    SUM(cs.Reputation) AS Reputation,
    SUM(cs.GoldBadges) AS GoldBadges,
    AVG(cs.AvgAnswerScore) AS AvgAnswerScore,
    SUM(cs.AnswerCount) AS AnswerCount,
    MAX(cs.MaxQuestionViews) AS MaxQuestionViews,
    AVG(cs.AvgViewDiff) AS AvgViewDiff,
    SUM(cs.HighScoreComments) AS HighScoreComments,
    AVG(cs.AvgBountyClosed) AS AvgBountyClosed,
    SUM(re.EditCount) AS EditCount,
    NULL AS ReputationRank,
    NULL AS ScoreRankPerGold
FROM CorrelatedSubqueryStats cs
LEFT OUTER JOIN RecentEdits re ON cs.UserId = re.UserId
ORDER BY ReputationRank;
