-- {"query": "59056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 683} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    STRING_AGG(DISTINCT ph.Comment, '; ') AS EditComments,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) AS UpDownVoteDifference,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (1,2,3,4,5,6)) AS EditCount,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 8) AS AvgBountyAmount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = p.OwnerUserId AND b2.Name IN ('Autobiographer', 'Yearling', 'Great Answer', 'Good Answer')) AS ReputationBadgesCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN Posts pt ON p.Id = pt.ParentId AND pt.PostTypeId = 4
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.CreationDate >= '2022-01-01' 
    AND p.PostTypeId IN (1,2)
    AND p.Score > 10
    AND u.Reputation > 1000
    AND (p.ViewCount > 100 OR p.AnswerCount > 0)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.ParentId
HAVING 
    COUNT(DISTINCT v.Id) > 0
    AND COUNT(DISTINCT c.Id) < 50
ORDER BY 
    p.ViewCount DESC,
    p.Score DESC,
    p.CreationDate DESC
LIMIT 1000;