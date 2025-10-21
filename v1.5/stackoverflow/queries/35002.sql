WITH user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        MAX(p.Score) AS MaxPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE
        u.CreationDate <= (TIMESTAMP '2024-10-01 12:34:56') - INTERVAL '1' YEAR
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
top_tags AS (
    SELECT
        pu.UserId,
        tag,
        cnt,
        ROW_NUMBER() OVER (PARTITION BY pu.UserId ORDER BY cnt DESC) AS rn
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            CAST(tag AS VARCHAR(255)) AS tag,
            COUNT(*) AS cnt
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT value AS tag
            FROM UNNEST(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS t(value)
        ) AS derived
        WHERE p.OwnerUserId IS NOT NULL
            AND p.PostTypeId = 1
            AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ) AS pu
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.MaxPostScore,
    ua.FirstPostDate,
    ua.LastPostDate,
    COALESCE(tt1.tag, '') AS TopTag1,
    COALESCE(tt2.tag, '') AS TopTag2,
    COALESCE(tt3.tag, '') AS TopTag3,
    COALESCE(b1.BadgeCount, 0) AS GoldBadges,
    COALESCE(b2.BadgeCount, 0) AS SilverBadges,
    COALESCE(b3.BadgeCount, 0) AS BronzeBadges
FROM
    user_activity ua
    LEFT JOIN top_tags tt1 ON tt1.UserId = ua.UserId AND tt1.rn = 1
    LEFT JOIN top_tags tt2 ON tt2.UserId = ua.UserId AND tt2.rn = 2
    LEFT JOIN top_tags tt3 ON tt3.UserId = ua.UserId AND tt3.rn = 3
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 1 GROUP BY UserId
    ) b1 ON b1.UserId = ua.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 2 GROUP BY UserId
    ) b2 ON b2.UserId = ua.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 3 GROUP BY UserId
    ) b3 ON b3.UserId = ua.UserId
WHERE
    ua.TotalPosts + ua.TotalComments + ua.TotalVotes > 500
ORDER BY
    ua.Reputation DESC,
    ua.TotalPosts DESC,
    ua.TotalVotes DESC
LIMIT 100;