-- {"query": "28029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1280} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
GoldBadgeUsers AS (
    SELECT 
        UserId,
        COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
    HAVING COUNT(*) >= 5
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.CommentCount,
    ua.UpvotesGiven,
    gbu.GoldBadges,
    COALESCE(ph.CloseReasons, '[]') AS CloseReasons,
    STRING_AGG(DISTINCT t.TagName, '; ') AS FrequentTags,
    (SELECT MAX(LastEditDate) FROM Posts p WHERE p.OwnerUserId = ua.UserId) AS LastEdit,
    ROUND(ua.CommentCount * 1.0 / NULLIF(ua.PostCount, 0), 2) AS CommentRatio,
    CASE 
        WHEN ua.PostRank <= 10 THEN 'Top Contributor'
        WHEN gbu.UserId IS NOT NULL THEN 'Gold Star'
        ELSE 'Active'
    END AS UserClass
FROM UserActivity ua
LEFT JOIN GoldBadgeUsers gbu ON ua.UserId = gbu.UserId
LEFT JOIN (
    SELECT 
        ph.UserId,
        JSON_AGG(DISTINCT crt.Name) AS CloseReasons
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::INT = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId
) ph ON ua.UserId = ph.UserId
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN (
    SELECT 
        Id,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1
) t ON p.Id = t.Id
WHERE 
    ua.PostCount > 100 
    AND (ua.CommentRatio > 0.5 OR ua.CommentRatio IS NULL)
    AND EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId = 8 
        AND v.BountyAmount > 50
    )
GROUP BY 
    ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, 
    ua.CommentCount, ua.UpvotesGiven, gbu.GoldBadges, ph.CloseReasons
ORDER BY 
    ua.Reputation DESC, 
    ua.PostRank
LIMIT 100;
