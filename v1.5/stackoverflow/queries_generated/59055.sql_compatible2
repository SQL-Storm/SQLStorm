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
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 1 THEN 'Question'
        ELSE 'Other'
    END AS PostTypeCategory,
    EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) AS SecondsSinceLastActivity,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.Score < 0 THEN 'Negative Score'
        ELSE 'Active'
    END AS PostStatus,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) AS UpDownVoteDifference
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, STRING_AGG(t.TagName, ', ') AS TagName
    FROM Posts p2
    JOIN Tags t ON POSITION(t.TagName IN p2.Tags) > 0
    WHERE p2.PostTypeId = 1
    GROUP BY p2.Id
) t ON p.Id = t.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.CreationDate >= DATE '2023-01-01'
    AND p.PostTypeId IN (1, 2)
    AND u.Reputation >= 100
    AND (p.Score >= 0 OR p.Score IS NULL)
GROUP BY 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName,
    u.Reputation,
    p.AcceptedAnswerId,
    p.PostTypeId,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.LastActivityDate,
    p.ParentId
HAVING COUNT(DISTINCT c.Id) > 0
    AND COUNT(DISTINCT v.Id) > 0
    AND COUNT(DISTINCT bh.Id) > 0
ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate DESC
LIMIT 1000;