-- {"query": "52052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 382} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT v.Id) AS TotalVotesReceived,
    COUNT(DISTINCT CASE WHEN pt.Id = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN pt.Id = 2 THEN p.Id END) AS AnswerCount,
    MAX(b.Date) AS LatestBadgeDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags,
    RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteRank
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT p.Id, t.TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
        LIMIT 3 -- Top 3 tags per post
    ) t
    WHERE p.Tags IS NOT NULL
    AND t.TagName <> ''
) t ON p.Id = t.Id
WHERE u.Reputation > 100
AND p.CreationDate >= '2010-01-01'::timestamp
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT v.Id) > 10
ORDER BY TotalVotesReceived DESC
LIMIT 1000;