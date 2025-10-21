-- {"query": "45035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 337}
SELECT
    p.Id AS PostId,
    u.DisplayName,
    t.TagName,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(p.Score) AS AveragePostScore,
    MAX(u.Reputation) AS UserMaxReputation,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS TotalLinkedPosts
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
JOIN
    Tags t ON t.Id IN (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    )
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
WHERE
    p.PostTypeId = 1
    AND u.Reputation > 1000
    AND p.CreationDate > '2015-01-01'
GROUP BY
    p.Id, u.DisplayName, t.TagName
HAVING
    COUNT(DISTINCT v.Id) > 10
ORDER BY
    TotalVotes DESC, UserMaxReputation DESC
LIMIT 500;
