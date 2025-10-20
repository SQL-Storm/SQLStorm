-- {"query": "19.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 340} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    MAX(p.LastActivityDate) AS LastActiveQuestionDate,
    STRING_AGG(DISTINCT t.TagName, ',') AS TopTags
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    UNNEST(string_to_array(p.Tags, '><')) WITH ORDINALITY AS t(TagName, ord)
        ON p.PostTypeId = 1
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    Posts tpost ON tpost.Id = pl.RelatedPostId
WHERE
    p.PostTypeId = 1
    AND u.AccountId IS NOT NULL
    AND (p.ClosedDate IS NULL OR p.ClosedDate > CURRENT_DATE - INTERVAL '2 years')
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    Reputation DESC,
    LastActiveQuestionDate DESC
LIMIT 100;