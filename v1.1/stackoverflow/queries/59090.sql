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
    COUNT(DISTINCT bh.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    MAX(ph.CreationDate) as LastActivityDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END as PostType,
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
        ELSE 'No Accepted Answer'
    END as AnswerStatus,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END as PostStatus
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, tags.TagName 
    FROM Posts p2 
    JOIN (
        SELECT Id, TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(Tags, '><'))) as TagName
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) tags ON p2.Id = tags.Id
    WHERE p2.PostTypeId = 1
) t ON p.Id = t.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId 
    AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
WHERE p.CreationDate >= DATE '2020-01-01' 
    AND p.CreationDate < DATE '2024-01-01'
    AND p.PostTypeId IN (1, 2)
    AND (p.Score >= 0 OR p.Score IS NULL)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.AcceptedAnswerId, p.ClosedDate, p.CommunityOwnedDate, p.PostTypeId
HAVING 
    COUNT(DISTINCT c.Id) > 10 
    OR COUNT(DISTINCT v.Id) > 50 
    OR COUNT(DISTINCT bh.Id) > 20
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    MAX(ph.CreationDate) DESC
LIMIT 1000;