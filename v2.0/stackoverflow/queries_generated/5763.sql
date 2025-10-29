-- {"query": "5763.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 302} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCount,
    AVG(COALESCE(p.Score,0)) AS AvgPostScore,
    SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
    MAX(p.CreationDate) AS MostRecentPostDate,
    STRING_AGG(DISTINCT t.Name, ',') AS TagsInPosts
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN LATERAL (
    SELECT DISTINCT tn.Name
    FROM unnest(string_to_array(p.Tags, '<>')) AS tn
) t ON true
WHERE
    u.Reputation > 1000
    AND u.AccountId IS NOT NULL
    AND (p.PostTypeId = 1 OR p.PostTypeId IS NULL)
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    COUNT(DISTINCT p.Id) > 5
ORDER BY
    TotalViews DESC, AvgPostScore DESC
LIMIT 100;