SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.Tags,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    MAX(v.CreationDate) AS LastVoteDate,
    MAX(bh.CreationDate) AS LastHistoryDate,
    MAX(c.CreationDate) AS LastCommentDate
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, t.TagName
    FROM Posts p2
    LEFT JOIN (
        SELECT Id, unnest(string_to_array(replace(replace(Tags, '<', ''), '>', ''), '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON p2.Id = t.Id
    WHERE p2.PostTypeId = 1
) t ON p.Id = t.PostId
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= DATE '2022-01-01'
    AND p.Score > 100
    AND u.Reputation > 1000
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.Tags
HAVING COUNT(DISTINCT c.Id) > 5 
    AND COUNT(DISTINCT v.Id) > 10
    AND COUNT(DISTINCT bh.Id) > 3
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;