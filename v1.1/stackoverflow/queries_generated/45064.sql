-- {"query": "45064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 342}
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    t.TagName,
    u.DisplayName AS AuthorName,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    MAX(u.Reputation) AS AuthorReputation,
    AVG(v2.Score) AS AverageRelatedPostScore
FROM
    Posts p
JOIN Tags t ON t.Id IN (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
)
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Posts v2 ON pl.RelatedPostId = v2.Id
WHERE
    p.PostTypeId = 1
    AND p.CreationDate > '2015-01-01'
    AND u.Reputation > 1000
GROUP BY
    p.Id, p.Title, p.CreationDate, t.TagName, u.DisplayName
HAVING
    COUNT(DISTINCT v.Id) > 10
ORDER BY
    VoteCount DESC, AuthorReputation DESC
LIMIT 500;
