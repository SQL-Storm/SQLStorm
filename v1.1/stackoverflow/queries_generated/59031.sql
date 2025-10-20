-- {"query": "59031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1176} 
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
    p.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as NetVoteCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadgeCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountActual,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,4,6)) as EditCount,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != '') as TagList,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) as LastEditDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) as LinkCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as AvgBountyAmount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as FavoriteCountActual,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1) as AcceptCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score > 0) as PositiveAnswerCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score < 0) as NegativeAnswerCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score = 0) as ZeroAnswerCount,
    COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END as PostStatus,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'User Owned' END as OwnershipStatus,
    COALESCE(p.ContentLicense, 'Creative Commons Attribution-SA 4.0') as ContentLicense,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (12,13,10,11)) as ActivityCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.OwnerUserId IS NOT NULL) as AnsweredByUsers,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.OwnerUserId IS NULL) as AnsweredByCommunity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) as TotalBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 2) as AnswerCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId IN (1,2)) as TotalPosts,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (4,12)) as OffensiveSpamCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.LastEditDate IS NOT NULL) as EditedAnswers,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.LastEditDate IS NULL) as UneditedAnswers
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId IN (1,2)
    AND p.CreationDate >= '2020-01-01'
    AND (p.Score >= 10 OR p.ViewCount >= 100)
    AND (p.Title IS NOT NULL AND LENGTH(p.Title) >= 10)
    AND p.Tags IS NOT NULL
ORDER BY p.Score DESC, p.CreationDate DESC
LIMIT 10000;