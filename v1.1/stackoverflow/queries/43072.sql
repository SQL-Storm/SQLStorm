WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.TotalPosts,
        ua.TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        u.LastAccessDate
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
    GROUP BY u.Id, u.DisplayName, u.Reputation, ua.TotalPosts, ua.TotalScore, u.LastAccessDate
    ORDER BY ua.TotalScore DESC, u.Reputation DESC
    LIMIT 10
)
SELECT 
    tc.Id,
    tc.DisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.TotalScore,
    tc.BadgeCount,
    ARRAY_AGG(DISTINCT t.TagName) AS TopTags,
    COUNT(p.Id) AS PostCount
FROM TopContributors tc
JOIN Posts p ON tc.DisplayName = p.OwnerDisplayName
JOIN (
    SELECT p_inner.Id AS post_id, u_tag.tag AS TagName, u_tag.pos
    FROM Posts p_inner
    CROSS JOIN LATERAL (
        SELECT split_tag.tag, ROW_NUMBER() OVER () AS pos
        FROM (
            SELECT regexp_split_to_table(substring(p_inner.Tags FROM 2 FOR char_length(p_inner.Tags) - 2), '><') AS tag
        ) AS split_tag
    ) u_tag
) t ON t.post_id = p.Id
WHERE p.PostTypeId = 1
GROUP BY tc.Id, tc.DisplayName, tc.Reputation, tc.TotalPosts, tc.TotalScore, tc.BadgeCount
ORDER BY tc.TotalScore DESC, PostCount DESC;