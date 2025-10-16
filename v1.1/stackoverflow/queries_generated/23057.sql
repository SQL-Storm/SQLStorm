-- {"query": "23057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 928} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.TagBased = 1
    GROUP BY b.UserId
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        CONCAT_WS(' ', p.Title, COALESCE(NULLIF(p.Tags, ''), 'No Tags')) AS PostDescription
    FROM Posts p
    WHERE p.PostTypeId = 1  -- Questions
    AND p.ClosedDate IS NULL
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
),
UserActivity AS (
    SELECT 
        au.UserId,
        au.DisplayName,
        au.Reputation,
        au.TotalPostScore,
        au.ReputationRank,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.LatestBadgeDate,
        COUNT(DISTINCT pm.PostId) AS QuestionCount,
        AVG(pm.Score) AS AvgQuestionScore,
        SUM(pm.PositiveComments) AS TotalPositiveComments,
        MAX(pm.PostDescription) AS SamplePost
    FROM ActiveUsers au
    LEFT OUTER JOIN BadgeSummary bs ON au.UserId = bs.UserId
    INNER JOIN PostMetrics pm ON au.UserId = pm.OwnerUserId
    WHERE au.ReputationRank <= 100
    AND (bs.GoldBadges > 0 OR bs.SilverBadges > 5)
    GROUP BY au.UserId, au.DisplayName, au.Reputation, au.TotalPostScore, au.ReputationRank,
             bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.LatestBadgeDate
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPostScore,
    ua.ReputationRank,
    COALESCE(ua.GoldBadges, 0) AS GoldBadges,
    COALESCE(ua.SilverBadges, 0) AS SilverBadges,
    COALESCE(ua.BronzeBadges, 0) AS BronzeBadges,
    ua.LatestBadgeDate,
    ua.QuestionCount,
    ua.AvgQuestionScore,
    ua.TotalPositiveComments,
    ua.SamplePost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT PostId FROM PostMetrics WHERE OwnerUserId = ua.UserId) AND v.VoteTypeId = 2) AS UpvotesReceived
FROM UserActivity ua
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS TotalPostScore,
    NULL AS ReputationRank,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS LatestBadgeDate,
    0 AS QuestionCount,
    0 AS AvgQuestionScore,
    0 AS TotalPositiveComments,
    'Inactive User' AS SamplePost,
    0 AS UpvotesReceived
FROM Users u
WHERE u.Id NOT IN (SELECT UserId FROM ActiveUsers)
AND u.CreationDate > '2020-01-01'
ORDER BY Reputation DESC;
