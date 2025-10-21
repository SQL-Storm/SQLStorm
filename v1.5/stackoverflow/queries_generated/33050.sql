-- {"query": "33050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 417} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    u.Reputation AS OwnerReputation,
    u.Views AS OwnerViews,
    ARRAY_AGG(DISTINCT t.TagName) AS Tags,
    ARRAY_AGG(DISTINCT pg.Name) FILTER (WHERE pg.Id IS NOT NULL) AS PostHistoryTypes,
    COUNT(bl.Id) AS LinkCount,
    COUNT(DISTINCT cl.UserId) AS CommentingUsers,
    EXTRACT(YEAR FROM p.CreationDate) AS YearCreated
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    PostLinks bl ON bl.PostId = p.Id
LEFT JOIN
    PostLinks bl2 ON bl2.RelatedPostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN
    PostHistoryTypes pg ON ph.PostHistoryTypeId = pg.Id
LEFT JOIN
    (SELECT DISTINCT PostId, UserId FROM Comments) cl ON cl.PostId = p.Id
LEFT JOIN
    Unnest(string_to_array(p.Tags, '><')) AS tag ON TRUE
LEFT JOIN
    Tags t ON t.TagName = tag
WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= date_trunc('year', CURRENT_DATE) - INTERVAL '2 years'
GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, u.Reputation, u.Views
ORDER BY
    p.CreationDate DESC
LIMIT 100;