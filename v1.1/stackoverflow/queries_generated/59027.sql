-- {"query": "59027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 901} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COUNT(DISTINCT c.Id) as CommentCountActual,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    STRING_AGG(DISTINCT ph.Comment, '; ') as EditComments,
    MAX(ph.CreationDate) as LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END as PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCountWithDeleted,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) as UpDownVoteCount,
    (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) as CommentCountWithDeleted,
    (SELECT COUNT(*) FROM Badges WHERE UserId = p.OwnerUserId) as UserBadgesCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 1) as UserQuestionsCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 2) as UserAnswersCount,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 1) as UserAvgQuestionScore,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 2) as UserAvgAnswerScore,
    (SELECT COUNT(*) FROM Votes WHERE UserId = p.OwnerUserId AND VoteTypeId = 5) as UserFavoritesCount,
    (SELECT COUNT(*) FROM Votes WHERE UserId = p.OwnerUserId AND VoteTypeId IN (6,7)) as UserCloseReopenCount,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId IN (10,11,12,13)) as PostHistoryCount,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = p.Id OR RelatedPostId = p.Id) as PostLinkCount,
    (SELECT COUNT(*) FROM Posts WHERE Id IN (SELECT RelatedPostId FROM PostLinks WHERE PostId = p.Id AND LinkTypeId = 3)) as DuplicateQuestionCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT Id, TagName 
    FROM Tags 
    WHERE TagName IS NOT NULL 
    ORDER BY Count DESC 
    LIMIT 100
) t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE p.PostTypeId IN (1,2) 
    AND p.CreationDate >= '2022-01-01'
    AND u.Reputation > 1000
    AND (p.Score > 0 OR p.ViewCount > 100)
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
         u.DisplayName, u.Reputation, p.AnswerCount, 
         p.CommentCount, p.FavoriteCount, p.PostTypeId, 
         p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId,
         p.OwnerUserId
HAVING COUNT(DISTINCT c.Id) >= 0
   AND COUNT(DISTINCT v.Id) >= 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;