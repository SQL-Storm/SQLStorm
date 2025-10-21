-- {"query": "59040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 885} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = u.Id AND b.Date >= p.CreationDate) as RecentBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2) as AnswerCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags, n, 1), ', ') 
     FROM generate_series(1, LENGTH(p.Tags)) n 
     WHERE SUBSTRING(p.Tags, n, 1) = '>') as TagCount,
    (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as AvgUpvoteRatio,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13)) as HistoryChanges,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.ParentId = p.Id AND p4.PostTypeId = 2 AND p4.Score > 0) as PositiveAnswers,
    (SELECT STRING_AGG(DISTINCT pt.Name, ', ') 
     FROM PostHistory ph2 
     JOIN PostHistoryTypes pt ON ph2.PostHistoryTypeId = pt.Id 
     WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (1,4,6)) as ModificationTypes,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.ParentId = p.Id AND p5.PostTypeId = 2 AND p5.CreationDate > p.CreationDate) as LateAnswers
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2020-01-01'
    AND p.Score > 100
    AND p.ViewCount > 1000
    AND u.Reputation > 5000
    AND u.LastAccessDate >= '2022-01-01'
    AND EXISTS (
        SELECT 1 FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.CreationDate >= '2021-01-01'
        AND c.Score > 0
    )
    AND EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.VoteTypeId IN (2,3)
        AND v.CreationDate >= '2021-01-01'
    )
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 12
        AND ph.CreationDate >= '2021-01-01'
    )
    AND NOT EXISTS (
        SELECT 1 FROM Posts p6 
        WHERE p6.ParentId = p.Id 
        AND p6.PostTypeId = 2 
        AND p6.CreationDate < p.CreationDate
        AND p6.Score > 0
    )
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT c.Id) > 5 
   AND COUNT(DISTINCT v.Id) > 10
   AND COUNT(DISTINCT pl.Id) > 2
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;