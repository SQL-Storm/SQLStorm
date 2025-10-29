SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCount,
    AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
    MAX(p.CreationDate) AS MostRecentPostDate,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagsInPosts
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN (
    SELECT
        p_inner.Id AS post_id,
        tn.value AS TagName
    FROM
        Posts p_inner,
        UNNEST(string_to_array(COALESCE(p_inner.Tags, ''), '<>')) AS tn(value)
) t ON t.post_id = p.Id
WHERE
    u.Reputation > 1000
    AND u.AccountId IS NOT NULL
    AND (p.PostTypeId = 1 OR p.PostTypeId IS NULL)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING
    COUNT(DISTINCT p.Id) > 5
ORDER BY
    TotalViews DESC,
    AvgPostScore DESC
LIMIT 100;