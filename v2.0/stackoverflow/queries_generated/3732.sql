-- {"query": "3732.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2318} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore
    FROM Users u
    WHERE u.Reputation > 1000
),
RecentActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(v.CreationDate) AS LastVoteDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagInfo AS (
    SELECT 
        t.TagName,
        t.Count AS TagUseCount,
        COALESCE(e.Title, 'No Excerpt') AS ExcerptTitle,
        COALESCE(w.Title, 'No Wiki') AS WikiTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(us.AvgPostScore, 2) AS AvgScore,
    COALESCE(ra.LastPostDate, TIMESTAMP '1970-01-01') AS LastPostDate,
    COALESCE(ra.LastVoteDate, TIMESTAMP '1970-01-01') AS LastVoteDate,
    CASE
        WHEN us.Reputation >= 20000 THEN 'Legendary'
        WHEN us.Reputation >= 10000 THEN 'Expert'
        WHEN us.Reputation >= 5000  THEN 'Advanced'
        ELSE 'Regular'
    END AS ReputationTier,
    STRING_AGG(DISTINCT ti.TagName, ', ') FILTER (WHERE ti.TagUseCount > 1000) AS PopularTags
FROM UserStats us
LEFT JOIN RecentActivity ra ON ra.UserId = us.Id AND ra.rn = 1
LEFT JOIN TagInfo ti ON ti.TagUseCount > 5000 AND ti.ExcerptTitle IS NOT NULL
WHERE (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 10
GROUP BY 
    us.Id, us.DisplayName, us.Reputation, us.Location,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.QuestionCount, us.AnswerCount, us.AvgPostScore,
    ra.LastPostDate, ra.LastVoteDate,
    ReputationTier
HAVING COUNT(ti.TagName) > 0
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

SELECT NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL

EXCEPT

SELECT 
    Id, DisplayName, Reputation, Location,
    GoldBadges, SilverBadges, BronzeBadges,
    QuestionCount, AnswerCount, AvgScore,
    LastPostDate, LastVoteDate, ReputationTier, PopularTags
FROM (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        ROUND(us.AvgPostScore, 2) AS AvgScore,
        COALESCE(ra.LastPostDate, TIMESTAMP '1970-01-01') AS LastPostDate,
        COALESCE(ra.LastVoteDate, TIMESTAMP '1970-01-01') AS LastVoteDate,
        CASE
            WHEN us.Reputation >= 20000 THEN 'Legendary'
            WHEN us.Reputation >= 10000 THEN 'Expert'
            WHEN us.Reputation >= 5000  THEN 'Advanced'
            ELSE 'Regular'
        END AS ReputationTier,
        NULL AS PopularTags
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.UserId = us.Id AND ra.rn = 1
) sub
ORDER BY Reputation DESC
OFFSET 0;
