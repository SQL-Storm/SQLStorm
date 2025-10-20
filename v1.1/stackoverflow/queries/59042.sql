-- {"query": "59042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 779} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCountActual,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN ph.Id END) AS EditCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) AS DeleteCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) AS UndeleteCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id END) AS CommunityOwnedCount,
    COUNT(DISTINCT pl.Id) AS LinkedPosts,
    STRING_AGG(DISTINCT bt.Name, ', ') AS BadgeNames,
    MAX(ph.CreationDate) AS LastEditDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
        ELSE 'Unknown'
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.Score > 100 THEN 'Highly Voted'
        WHEN p.ViewCount > 1000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS PostClassification
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Badges bt ON u.Id = bt.UserId
WHERE p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    AND p.PostTypeId IN (1, 2)
    AND u.Reputation > 1000
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.Tags, 
    p.PostTypeId, 
    p.ClosedDate, 
    p.CommunityOwnedDate,
    p.LastActivityDate
HAVING 
    COUNT(DISTINCT v.Id) > 5 
    AND COUNT(DISTINCT c.Id) > 10
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.CreationDate DESC
LIMIT 1000;