-- {"query": "33017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 531} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesCount,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    ARRAY_AGG(DISTINCT t.TagName) AS Tags,
    ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPosts,
    ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS Duplicates,
    JSON_AGG(DISTINCT jsonb_build_object('HistoryType', pht.Name, 'ChangeDate', ph.CreationDate)) AS PostHistory
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    PostTags ptg ON p.Id = ptg.PostId
LEFT JOIN
    Tags t ON ptg.TagId = t.Id
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN
    PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE
    pt.Name IN ('Question', 'Answer')
    AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount,
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
    p.CreationDate DESC
LIMIT 100;