WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesGiven,
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
),
CloseReasonsAgg AS (
    SELECT 
        ph.UserId,
        -- dialect-neutral JSON array build using string aggregation
        '[' || STRING_AGG(DISTINCT '"' || REPLACE(crt.Name, '"', '""') || '"', ',') || ']' AS CloseReasons
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId
),
PostTags AS (
    SELECT 
        Id,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags)-2), '><')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.CommentCount,
    ua.UpvotesGiven,
    gbu.GoldBadges,
    COALESCE(cra.CloseReasons, '[]') AS CloseReasons,
    STRING_AGG(DISTINCT t.TagName, '; ') AS FrequentTags,
    (SELECT MAX(p2.LastEditDate) FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId) AS LastEdit,
    ROUND(ua.CommentCount * 1.0 / NULLIF(ua.PostCount, 0), 2) AS CommentRatio,
    CASE 
        WHEN ua.PostRank <= 10 THEN 'Top Contributor'
        WHEN gbu.UserId IS NOT NULL THEN 'Gold Star'
        ELSE 'Active'
    END AS UserClass,
    ua.PostRank
FROM UserActivity ua
LEFT JOIN GoldBadgeUsers gbu ON ua.UserId = gbu.UserId
LEFT JOIN CloseReasonsAgg cra ON ua.UserId = cra.UserId
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN PostTags t ON p.Id = t.Id
WHERE 
    ua.PostCount > 100 
    AND (ROUND(ua.CommentCount * 1.0 / NULLIF(ua.PostCount, 0), 2) > 0.5 OR ua.CommentCount IS NULL)
    AND EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = ua.UserId 
        AND v.VoteTypeId = 8 
        AND v.BountyAmount > 50
    )
GROUP BY 
    ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, 
    ua.CommentCount, ua.UpvotesGiven, gbu.GoldBadges, cra.CloseReasons, ua.PostRank, gbu.UserId
ORDER BY 
    ua.Reputation DESC, 
    ua.PostRank
LIMIT 100;