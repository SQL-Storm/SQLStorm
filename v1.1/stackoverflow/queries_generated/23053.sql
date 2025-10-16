-- {"query": "23053.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 972} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
),
BadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) DESC) AS VoteRank
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    GROUP BY v.PostId, p.OwnerUserId
),
CorrelatedSubqueryExample AS (
    SELECT 
        us.UserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.UserId AND c.Score > 5) AS HighScoreComments
    FROM UserStats us
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.UserLocation,
    us.RepRank,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    COALESCE(us.AvgPostScore, 0) AS AvgPostScore,
    us.LatestPostDate,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    SUBSTRING(bs.BadgeNames, 1, 100) AS TopBadges,
    tvp.NetVotes AS TopPostNetVotes,
    cse.HighScoreComments,
    CASE 
        WHEN us.RepRank <= 10 THEN 'Elite'
        WHEN us.RepRank <= 100 THEN 'Veteran'
        ELSE 'Regular'
    END AS UserTier,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = us.UserId AND p2.CreationDate > us.LatestPostDate - INTERVAL '1 YEAR') AS RecentAvgScore
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
LEFT JOIN TopVotedPosts tvp ON us.UserId = tvp.OwnerUserId AND tvp.VoteRank = 1
LEFT JOIN CorrelatedSubqueryExample cse ON us.UserId = cse.UserId
WHERE us.RepRank <= 1000
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    NULL AS RepRank,
    0 AS TotalPosts,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS AvgPostScore,
    NULL AS LatestPostDate,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS TopBadges,
    NULL AS TopPostNetVotes,
    0 AS HighScoreComments,
    'Inactive' AS UserTier,
    NULL AS RecentAvgScore
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.Id IS NULL AND u.CreationDate < CURRENT_DATE - INTERVAL '5 YEARS'
ORDER BY RepRank ASC NULLS LAST, GoldBadges DESC;
