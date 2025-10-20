-- {"query": "59082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1707} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
        0
    ) AS Upvotes,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
        0
    ) AS Downvotes,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
        0
    ) AS CommentCount,
    COALESCE(
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 6)),
        0
    ) AS EditCount,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1),
        0
    ) AS GoldBadges,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2),
        0
    ) AS SilverBadges,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3),
        0
    ) AS BronzeBadges,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Other'
    END AS PostStatus,
    COALESCE(
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3),
        0
    ) AS DuplicateCount,
    COALESCE(
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1),
        0
    ) AS LinkedToCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11) AS ReopenCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12) AS DeleteCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 13) AS UndeleteCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 14) AS LockCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 15) AS UnlockCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19) AS ProtectCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 20) AS UnprotectCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 35) AS MigrationAwayCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 36) AS MigrationHereCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 16) AS CommunityOwnedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 31) AS DiscussionMovedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 52) AS HotNetworkCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 53) AS HotRemovedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) AS EditAppliedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 22) AS UnmergedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 18) AS MergedQuestionCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 50) AS CommunityBumpCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 25) AS TweetedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 33) AS NoticeAddedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 34) AS NoticeRemovedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 37) AS MergeSourceCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 38) AS MergeDestinationCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 66) AS CreatedFromWizardCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.CreationDate >= '2022-01-01'
    AND p.Score >= 0
    AND p.ViewCount >= 0
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.AcceptedAnswerId IS NOT NULL
    AND u.Reputation >= 10000
    AND (
        EXISTS (
            SELECT 1 FROM Comments c 
            WHERE c.PostId = p.Id 
                AND c.CreationDate >= '2022-01-01'
                AND c.Score >= 5
        )
        OR EXISTS (
            SELECT 1 FROM PostHistory ph
            WHERE ph.PostId = p.Id
                AND ph.CreationDate >= '2022-01-01'
                AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
        )
        OR EXISTS (
            SELECT 1 FROM Badges b
            WHERE b.UserId = p.OwnerUserId
                AND b.Date >= '2022-01-01'
                AND b.Class IN (1, 2, 3)
        )
    )
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;