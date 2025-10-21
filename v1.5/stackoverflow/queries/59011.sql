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
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    STRING_AGG(DISTINCT bt.Name, ', ') AS Badges,
    STRING_AGG(DISTINCT COALESCE(ph.Comment, ''), ' | ') AS HistoryComments
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT DISTINCT p2.Id AS PostId, t.TagName
    FROM Posts p2
    JOIN (
        SELECT Id, TRIM(BOTH '><' FROM UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><'))) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags <> ''
    ) AS tag_table ON p2.Id = tag_table.Id
    JOIN Tags t ON tag_table.TagName = t.TagName
) t ON p.Id = t.PostId
LEFT JOIN Badges bt ON u.Id = bt.UserId
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= DATE '2020-01-01'
    AND p.Score > 100
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.Tags
HAVING 
    COUNT(DISTINCT c.Id) > 5 
    AND COUNT(DISTINCT v.Id) > 10
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC
LIMIT 1000;