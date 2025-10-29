SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagNames,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    SUM(CASE WHEN b.Id IS NOT NULL AND b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Id IS NOT NULL AND b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Id IS NOT NULL AND b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
    SELECT
        p2.Id AS post_id,
        TRIM(BOTH ' ' FROM REPLACE(tag, '><', '')) AS tag
    FROM Posts p2
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(p2.Tags, ',')) AS tag
    ) s
) tagg ON tagg.post_id = p.Id
LEFT JOIN Tags t ON LOWER(t.TagName) = LOWER(tagg.tag)
WHERE
    u.AccountId IS NOT NULL
    AND u.Reputation > 100
    AND (p.PostTypeId = 1 OR p.PostTypeId IS NULL)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate
HAVING
    COUNT(DISTINCT p.Id) > 5
ORDER BY
    TotalViews DESC,
    AvgPostScore DESC
LIMIT 100;