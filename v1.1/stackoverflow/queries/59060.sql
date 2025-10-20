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
    CAST(EXTRACT(epoch FROM (COALESCE(p.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - p.CreationDate))/86400 AS INTEGER) as AgeInDays,
    (SELECT COUNT(*) FROM Posts AS p_answers WHERE p_answers.ParentId = p.Id AND p_answers.PostTypeId = 2) as AnswerCount,
    (SELECT COUNT(*) FROM Votes AS v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId IN (2,3)) as UpDownVotes,
    (SELECT COUNT(*) FROM Votes AS v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 5) as FavoriteCount,
    (SELECT COUNT(*) FROM Badges AS b WHERE b.UserId = p.OwnerUserId AND b.Name IN ('Populist', 'Nice Answer', 'Good Answer', 'Great Answer')) as BadgeCount,
    (SELECT COUNT(*) FROM PostHistory AS ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (10,11,12,13)) as ClosureHistory,
    (SELECT STRING_AGG(u2.DisplayName || ':' || CAST(v4.VoteTypeId AS varchar), '; ' ORDER BY v4.CreationDate DESC) 
     FROM Votes v4 
     JOIN Users u2 ON v4.UserId = u2.Id 
     WHERE v4.PostId = p.Id AND v4.VoteTypeId IN (2,3)
     LIMIT 10) as RecentVotes,
    (SELECT COUNT(*) FROM PostLinks AS pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostLinks AS pl2 WHERE pl2.RelatedPostId = p.Id AND pl2.LinkTypeId = 3) as IsDuplicateOfCount,
    (SELECT COUNT(*) FROM PostHistory AS ph3 WHERE ph3.PostId = p.Id AND ph3.PostHistoryTypeId = 24) as EditCount,
    (SELECT COUNT(*) FROM PostHistory AS ph4 WHERE ph4.PostId = p.Id AND ph4.PostHistoryTypeId IN (10,11)) as CloseReopenCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, tags.TagName 
    FROM Posts p2 
    JOIN (
        SELECT Id, regexp_split_to_table(TRIM(BOTH '<>' FROM Tags), '><') as TagName 
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags <> ''
    ) tags ON p2.Id = tags.Id
    WHERE p2.PostTypeId = 1
) t ON p.Id = t.PostId
WHERE p.CreationDate IS NOT NULL
    AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '2 years')
    AND p.PostTypeId IN (1,2)
    AND p.ViewCount > 0
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, 
    p.AcceptedAnswerId, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.OwnerUserId
HAVING COUNT(DISTINCT c.Id) >= 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;