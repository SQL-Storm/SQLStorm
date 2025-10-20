SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as AvgScoreLast10Posts,
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
    END as PostType,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12, 13, 14, 15) THEN ph.Id END) as ClosedReopenedDeletedCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.Id END) as SuggestedEditCount,
    MAX(ph.CreationDate) as LastActivity,
    (
      SELECT u2.DisplayName
      FROM Posts p2
      INNER JOIN Users u2 ON p2.OwnerUserId = u2.Id
      WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2
      ORDER BY p2.Score DESC
      LIMIT 1
    ) as HighestScoringAnswerOwner,
    (
      SELECT COUNT(*)
      FROM Badges b
      INNER JOIN Posts p3 ON b.UserId = p3.OwnerUserId
      WHERE p3.Id = p.Id
    ) as BadgeCountForPostOwner,
    (
      SELECT COUNT(*)
      FROM Posts p4
      WHERE p4.ParentId = p.Id AND p4.PostTypeId = 2
    ) as AnswerCount,
    u.Id as OwnerId
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT p5.Id as PostId, t.TagName
    FROM Posts p5
    INNER JOIN (
        SELECT Id, TagName
        FROM Tags
        WHERE TagName IN (SELECT DISTINCT TagName FROM Tags WHERE Count > 1000)
    ) t ON p5.Tags LIKE '%' || t.TagName || '%'
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATE '2018-01-01'
  AND p.CreationDate < DATE '2023-01-01'
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
  AND p.Score IS NOT NULL
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.PostTypeId,
    u.Id
HAVING 
    COUNT(DISTINCT ph.Id) > 0 
    AND COUNT(DISTINCT c.Id) >= 0
ORDER BY 
    p.CreationDate DESC,
    p.Score DESC
OFFSET 10000 ROWS FETCH NEXT 50000 ROWS ONLY;