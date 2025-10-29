-- {"query": "5413.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 417} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.AccountId,
    COALESCE(b.GoldCount, 0) AS GoldBadges,
    COALESCE(b.SilverCount, 0) AS SilverBadges,
    COALESCE(b.BronzeCount, 0) AS BronzeBadges,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    STRING_AGG(DISTINCT pt.Name, ',') AS PostTypeNames,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS LastUpvoteDate,
    MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 3) AS LastDownvoteDate,
    SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
    MIN(p.LastActivityDate) AS EarliestActivity
FROM
    Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
WHERE
    u.AccountId IS NOT NULL
    AND u.Reputation > 10
    AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2, 3, 4, 5))
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.AccountId
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    GoldBadges DESC,
    BronzeBadges ASC,
    LastPostDate DESC
LIMIT 100;