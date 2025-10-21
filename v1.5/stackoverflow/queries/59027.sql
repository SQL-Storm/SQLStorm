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
    COUNT(DISTINCT c.Id) AS CommentCountActual,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    STRING_AGG(DISTINCT ph.Comment, '; ') AS EditComments,
    MAX(ph.CreationDate) AS LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END AS PostStatus,
    (SELECT COUNT(*) FROM Posts AS t1 WHERE t1.ParentId = p.Id AND t1.PostTypeId = 2) AS AnswerCountWithDeleted,
    (SELECT COUNT(*) FROM Votes AS t2 WHERE t2.PostId = p.Id AND t2.VoteTypeId IN (2,3)) AS UpDownVoteCount,
    (SELECT COUNT(*) FROM Comments AS t3 WHERE t3.PostId = p.Id) AS CommentCountWithDeleted,
    (SELECT COUNT(*) FROM Badges AS t4 WHERE t4.UserId = p.OwnerUserId) AS UserBadgesCount,
    (SELECT COUNT(*) FROM Posts AS t5 WHERE t5.OwnerUserId = p.OwnerUserId AND t5.PostTypeId = 1) AS UserQuestionsCount,
    (SELECT COUNT(*) FROM Posts AS t6 WHERE t6.OwnerUserId = p.OwnerUserId AND t6.PostTypeId = 2) AS UserAnswersCount,
    (SELECT AVG(t7.Score) FROM Posts AS t7 WHERE t7.OwnerUserId = p.OwnerUserId AND t7.PostTypeId = 1) AS UserAvgQuestionScore,
    (SELECT AVG(t8.Score) FROM Posts AS t8 WHERE t8.OwnerUserId = p.OwnerUserId AND t8.PostTypeId = 2) AS UserAvgAnswerScore,
    (SELECT COUNT(*) FROM Votes AS t9 WHERE t9.UserId = p.OwnerUserId AND t9.VoteTypeId = 5) AS UserFavoritesCount,
    (SELECT COUNT(*) FROM Votes AS t10 WHERE t10.UserId = p.OwnerUserId AND t10.VoteTypeId IN (6,7)) AS UserCloseReopenCount,
    (SELECT COUNT(*) FROM PostHistory AS t11 WHERE t11.PostId = p.Id AND t11.PostHistoryTypeId IN (10,11,12,13)) AS PostHistoryCount,
    (SELECT COUNT(*) FROM PostLinks AS t12 WHERE t12.PostId = p.Id OR t12.RelatedPostId = p.Id) AS PostLinkCount,
    (SELECT COUNT(*) FROM Posts AS t13 WHERE t13.Id IN (SELECT RelatedPostId FROM PostLinks WHERE PostId = p.Id AND LinkTypeId = 3)) AS DuplicateQuestionCount
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
) t ON POSITION(t.TagName IN p.Tags) > 0
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= TIMESTAMP '2022-01-01'
  AND u.Reputation > 1000
  AND (p.Score > 0 OR p.ViewCount > 100)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.AnswerCount, 
    p.CommentCount, p.FavoriteCount, p.PostTypeId, 
    p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId, 
    p.OwnerUserId
HAVING COUNT(DISTINCT c.Id) >= 0
   AND COUNT(DISTINCT v.Id) >= 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;