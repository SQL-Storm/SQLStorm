-- {"query": "28002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1449} 
WITH BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
), PostStats AS (
    SELECT 
        OwnerUserId,
        AVG(Score) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersGiven,
        SUM(ViewCount) / NULLIF(COUNT(*), 0) AS AvgViewsPerPost
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT 
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    ps.AvgPostScore,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(Tags, 2, LENGTH(Tags)-2), ', ') 
     FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL) AS AllTags,
    COALESCE(v.UpVotes, 0) + COALESCE(v.DownVotes, 0) AS TotalVotes,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = u.Id 
     AND ph.PostHistoryTypeId IN (5, 6, 7)) AS EditActions,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.AcceptedAnswerId IS NOT NULL
        ) THEN 1 
        ELSE 0 
    END AS HasAcceptedAnswer,
    DENSE_RANK() OVER (PARTITION BY bs.GoldBadges > 0 ORDER BY u.Reputation DESC) AS EliteRepRank
FROM Users u
LEFT JOIN BadgeSummary bs ON u.Id = bs.UserId
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
) v ON u.Id = v.UserId
WHERE u.Reputation > 1000
    OR bs.GoldBadges >= 1
    OR ps.AvgPostScore > 10
UNION ALL
SELECT 
    -1 AS UserId,
    'Community' AS DisplayName,
    NULL, NULL, NULL, NULL, NULL,
    (SELECT COUNT(*) FROM Comments WHERE UserId IS NULL),
    NULL,
    (SELECT COUNT(*) FROM Votes WHERE UserId IS NULL),
    (SELECT COUNT(*) FROM PostHistory WHERE UserId IS NULL),
    0,
    NULL
ORDER BY EliteRepRank NULLS LAST, ReputationRank
LIMIT 100;