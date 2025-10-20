-- {"query": "59063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1167} 
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
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.DeletionDate IS NULL) as AnswerCount,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Date >= p.CreationDate) as RecentBadges,
    (SELECT STRING_AGG(ph.Comment, ' | ') FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13) AND ph.CreationDate >= p.CreationDate ORDER BY ph.CreationDate DESC LIMIT 5) as RecentPostHistory,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (17,35,36)) as MigrationCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (33,34)) as NoticeCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (19,20)) as ProtectionCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as BountyStartCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) as BountyCloseCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = p.OwnerUserId AND p3.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = p.OwnerUserId AND p4.PostTypeId = 2) as AnswerCount,
    (SELECT AVG(p5.Score) FROM Posts p5 WHERE p5.OwnerUserId = p.OwnerUserId AND p5.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p6.Score) FROM Posts p6 WHERE p6.OwnerUserId = p.OwnerUserId AND p6.PostTypeId = 2) as AvgAnswerScore,
    (SELECT MAX(p7.Score) FROM Posts p7 WHERE p7.OwnerUserId = p.OwnerUserId AND p7.PostTypeId = 1) as MaxQuestionScore,
    (SELECT MAX(p8.Score) FROM Posts p8 WHERE p8.OwnerUserId = p.OwnerUserId AND p8.PostTypeId = 2) as MaxAnswerScore,
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = p.OwnerUserId) as CommentCountByOwner,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.UserId = p.OwnerUserId AND v2.VoteTypeId IN (1,2,3)) as VoteActivityByOwner,
    (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = p.OwnerUserId AND b2.Date >= '2023-01-01') as RecentBadgeCount,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT t.TagName 
        FROM Tags t 
        WHERE POSITION('<'||t.TagName||'>' IN p.Tags) > 0
        ORDER BY t.Count DESC
        LIMIT 5
    ) t) as TopTags
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
AND p.CreationDate >= '2023-01-01'
AND p.CreationDate <= '2023-12-31'
AND p.Score >= 10
AND p.ViewCount >= 100
AND EXISTS (
    SELECT 1 FROM Votes v 
    WHERE v.PostId = p.Id 
    AND v.VoteTypeId IN (1,2,3) 
    AND v.CreationDate >= '2023-01-01'
)
AND EXISTS (
    SELECT 1 FROM Comments c 
    WHERE c.PostId = p.Id 
    AND c.CreationDate >= '2023-01-01'
)
AND p.AnswerCount > 0
AND p.CommentCount > 0
AND p.FavoriteCount > 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 10000;