-- {"query": "59060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 860} 
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
    MAX(ph.CreationDate) as LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Unanswered Question'
        ELSE 'Other'
    END as PostTypeDescription,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.Score < 0 THEN 'Negative Score'
        ELSE 'Active'
    END as Status,
    DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as AgeInDays,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) as UpDownVotes,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 5) as FavoriteCount,
    (SELECT COUNT(*) FROM Badges WHERE UserId = p.OwnerUserId AND Name IN ('Populist', 'Nice Answer', 'Good Answer', 'Great Answer')) as BadgeCount,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId IN (10,11,12,13)) as ClosureHistory,
    (SELECT STRING_AGG(CONCAT(u2.DisplayName, ':', v.VoteTypeId), '; ') 
     FROM Votes v 
     JOIN Users u2 ON v.UserId = u2.Id 
     WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3) 
     ORDER BY v.CreationDate DESC 
     LIMIT 10) as RecentVotes,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = p.Id AND LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostLinks WHERE RelatedPostId = p.Id AND LinkTypeId = 3) as IsDuplicateOfCount,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId = 24) as EditCount,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId IN (10,11)) as CloseReopenCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT PostId, TagName 
    FROM Posts p2 
    JOIN (
        SELECT Id, unnest(string_to_array(Tags, '><')) as TagName 
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) tags ON p2.Id = tags.Id
    WHERE p2.PostTypeId = 1
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
    AND p.PostTypeId IN (1,2)
    AND p.ViewCount > 0
    AND u.Reputation > 1000
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.AcceptedAnswerId, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.Score
HAVING COUNT(DISTINCT c.Id) >= 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;