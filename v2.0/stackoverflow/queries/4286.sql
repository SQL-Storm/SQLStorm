-- {"query": "4286.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1921}
WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text AS HistoryText,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
PostEdits AS (
    SELECT
        rph1.PostId,
        rph1.CreationDate AS LastEditDate,
        rph1.UserId AS LastEditorUserId,
        rph1.Comment AS LastEditComment,
        (SELECT ph1.Text FROM PostHistory ph1 WHERE ph1.PostId = rph1.PostId AND ph1.PostHistoryTypeId = 1 ORDER BY ph1.CreationDate DESC LIMIT 1) AS InitialTitle,
        (SELECT ph2.Text FROM PostHistory ph2 WHERE ph2.PostId = rph1.PostId AND ph2.PostHistoryTypeId = 2 ORDER BY ph2.CreationDate DESC LIMIT 1) AS InitialBody,
        (SELECT ph3.Text FROM PostHistory ph3 WHERE ph3.PostId = rph1.PostId AND ph3.PostHistoryTypeId = 3 ORDER BY ph3.CreationDate DESC LIMIT 1) AS InitialTags,
        rph1.HistoryText AS CurrentBodySnapshot,
        CASE WHEN rph1.PostHistoryTypeId = 4 THEN rph1.HistoryText ELSE NULL END AS CurrentTitleSnapshot,
        CASE WHEN rph1.PostHistoryTypeId = 6 THEN rph1.HistoryText ELSE NULL END AS CurrentTagsSnapshot
    FROM RankedPostHistory rph1
    WHERE rph1.rn = 1
),
UserReputationTrend AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 14 THEN 1 END) AS LockVotes,
        (
            SELECT COUNT(*)
            FROM Votes v
            WHERE v.UserId = u.Id AND v.VoteTypeId = 2
        ) AS GivenUpVotes
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
PostPerformance AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.ClosedDate,
        COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
        CASE
            WHEN p.Score > 100 AND p.ViewCount > 10000 THEN 'HighPerformance'
            WHEN p.Score < 0 OR p.ViewCount < 100 THEN 'LowPerformance'
            WHEN p.AnswerCount > 5 AND p.FavoriteCount > 10 THEN 'Engagement'
            ELSE 'Standard'
        END AS PerformanceCategory,
        pe.LastEditDate,
        pe.LastEditorUserId,
        pe.LastEditComment,
        CASE
            WHEN pe.InitialTitle IS NOT NULL AND pe.CurrentTitleSnapshot IS NOT NULL AND pe.InitialTitle <> pe.CurrentTitleSnapshot THEN 'TitleEdited'
            WHEN pe.InitialBody IS NOT NULL AND pe.CurrentBodySnapshot IS NOT NULL AND LENGTH(pe.InitialBody) <> LENGTH(pe.CurrentBodySnapshot) THEN 'BodyEdited'
            WHEN pe.InitialTags IS NOT NULL AND pe.CurrentTagsSnapshot IS NOT NULL AND pe.InitialTags <> pe.CurrentTagsSnapshot THEN 'TagsEdited'
            ELSE 'NoSpecificEdit'
        END AS EditType
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostEdits pe ON p.Id = pe.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
)
SELECT
    pp.PostId,
    pp.PostType,
    pp.Title,
    pp.Score,
    pp.ViewCount,
    pp.FavoriteCount,
    pp.AnswerCount,
    pp.CommentCount,
    pp.CreationDate AS PostCreationDate,
    pp.ClosedDate,
    pp.OwnerDisplayName,
    pp.PerformanceCategory,
    pp.EditType,
    urt.Reputation AS OwnerReputation,
    urt.UserCreationDate,
    urt.CloseVotes,
    urt.LockVotes,
    urt.GivenUpVotes,
    CASE WHEN pp.ClosedDate IS NOT NULL AND pp.ClosedDate > pp.CreationDate THEN 'ClosedAfterCreation' ELSE 'NormalStatus' END AS ClosureStatus,
    CASE WHEN pp.OwnerUserId = -1 THEN 'CommunityOwned' ELSE 'UserOwned' END AS OwnershipStatus,
    (SUBSTRING(pp.Title FROM 1 FOR GREATEST(5, LEAST(20, CAST(FLOOR(pp.Score / 5.0) AS INTEGER)))) || '|' || COALESCE(pp.LastEditComment, 'NoComment')) AS ProcessedTitleAndComment,
    LAG(pp.Score, 1, 0) OVER (PARTITION BY pp.PostType ORDER BY pp.CreationDate) AS PreviousPostScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pp.PostId AND c.Score > 0) AS PositiveCommentsCount
FROM PostPerformance pp
LEFT JOIN UserReputationTrend urt ON pp.OwnerUserId = urt.UserId
WHERE pp.Score > -5 AND pp.ViewCount > 10 AND urt.Reputation > 100

UNION ALL

SELECT
    p.Id,
    pt.Name,
    p.Title,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.ClosedDate,
    COALESCE(u.DisplayName, p.OwnerDisplayName),
    'EdgeCase' AS PerformanceCategory,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12) THEN 'Deleted'
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19) THEN 'Protected'
        ELSE 'OtherEdge'
    END AS EditType,
    urt.Reputation,
    urt.UserCreationDate,
    urt.CloseVotes,
    urt.LockVotes,
    urt.GivenUpVotes,
    CASE WHEN p.ClosedDate IS NOT NULL AND p.ClosedDate > p.CreationDate THEN 'ClosedAfterCreation' ELSE 'NormalStatus' END AS ClosureStatus,
    CASE WHEN p.OwnerUserId = -1 THEN 'CommunityOwned' ELSE 'UserOwned' END AS OwnershipStatus,
    (SUBSTRING(p.Title FROM 1 FOR GREATEST(5, LEAST(20, CAST(FLOOR(p.Score / 5.0) AS INTEGER)))) || '|' || COALESCE(pe.LastEditComment, 'NoComment')) AS ProcessedTitleAndComment,
    LAG(p.Score, 1, 0) OVER (PARTITION BY pt.Name ORDER BY p.CreationDate) AS PreviousPostScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentsCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserReputationTrend urt ON p.OwnerUserId = urt.UserId
LEFT JOIN PostEdits pe ON p.Id = pe.PostId
WHERE p.Score < -5 OR p.ViewCount < 5
ORDER BY PostCreationDate DESC
LIMIT 1000;