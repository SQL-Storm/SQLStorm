-- {"query": "23052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 895} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS ScoreRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS PrevViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount IS NOT NULL
),
BadgeInfo AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ') AS GoldBadges,
        COUNT(*) AS GoldBadgeCount
    FROM Badges b
    WHERE b.Class = 1 -- Gold
    GROUP BY b.UserId
),
EditsAndVotes AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = ph.PostId) AS Upvotes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9) -- Edits
    GROUP BY ph.PostId
)
SELECT 
    us.UserId,
    COALESCE(us.DisplayName, 'Anonymous') AS UserName,
    us.Reputation,
    us.PostCount,
    us.TotalScore,
    us.ScoreRank,
    tq.Title,
    tq.ViewCount,
    CASE 
        WHEN tq.ViewCount > 10000 THEN 'High Views' 
        WHEN tq.ViewCount BETWEEN 1000 AND 10000 THEN 'Medium Views' 
        ELSE 'Low Views' 
    END AS ViewCategory,
    NULLIF(tq.PrevViewCount, 0) AS PreviousTopViewCount,
    COALESCE(bi.GoldBadges, 'No Gold Badges') AS GoldBadges,
    bi.GoldBadgeCount,
    ev.EditCount,
    ev.Upvotes,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = us.UserId AND PostTypeId = 2) AS AvgAnswerScore, -- Correlated subquery
    UPPER(SUBSTRING(tq.Tags, 2, LENGTH(tq.Tags)-2)) AS CleanTags -- String expression
FROM UserStats us
LEFT OUTER JOIN TopQuestions tq ON us.UserId = tq.OwnerUserId 
    AND tq.ViewCount = (SELECT MAX(ViewCount) FROM Posts WHERE OwnerUserId = us.UserId AND PostTypeId = 1) -- Correlated subquery for max view question
LEFT OUTER JOIN BadgeInfo bi ON us.UserId = bi.UserId
INNER JOIN EditsAndVotes ev ON tq.PostId = ev.PostId
WHERE tq.PositiveComments > 5 OR ev.Upvotes > 10
UNION
SELECT 
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    0 AS PostCount,
    0 AS TotalScore,
    NULL AS ScoreRank,
    NULL AS Title,
    NULL AS ViewCount,
    NULL AS ViewCategory,
    NULL AS PreviousTopViewCount,
    'Special User' AS GoldBadges,
    0 AS GoldBadgeCount,
    0 AS EditCount,
    0 AS Upvotes,
    NULL AS AvgAnswerScore,
    NULL AS CleanTags
FROM Users u
WHERE u.Reputation > 100000 AND u.Id NOT IN (SELECT UserId FROM UserStats)
ORDER BY Reputation DESC
LIMIT 100;