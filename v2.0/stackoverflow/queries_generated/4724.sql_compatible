WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
AggregatedPostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u_owner.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN
                EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate))/86400
            ELSE NULL
        END AS DaysToClose,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS InteractionCount,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        REPLACE(REPLACE(p.Tags, '><', '> <'), '<', '') AS FormattedTags,
        CAST(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2)) AS VARCHAR(100)) AS FirstTag,
        ROW_NUMBER() OVER(ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id,
        p.PostTypeId,
        pt.Name,
        p.OwnerUserId,
        u_owner.DisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.Tags
)
SELECT
    ags.PostId,
    ags.PostTypeName,
    ags.OwnerDisplayName,
    ags.PostCreationDate,
    ags.Score,
    ags.ViewCount,
    ags.InteractionCount,
    ags.DaysToClose,
    ags.FormattedTags,
    ags.FirstTag,
    rpe.EditorDisplayName AS LastEditorDisplayName,
    rpe.CreationDate AS LastEditDate,
    ags.UpVotes,
    ags.DownVotes,
    COALESCE(ags.Score, 0) * (ags.UpVotes - ags.DownVotes) AS WeightedScore,
    CASE
        WHEN ags.PostTypeName = 'Question' AND ags.AnswerCount > 0 THEN CAST(ags.Score AS DOUBLE PRECISION) / ags.AnswerCount
        ELSE NULL
    END AS ScorePerAnswer,
    CASE
        WHEN ags.PostTypeName = 'Question' THEN
            (SELECT COUNT(*)
             FROM PostLinks pl
             WHERE pl.PostId = ags.PostId AND pl.LinkTypeId = 3)
        ELSE NULL
    END AS DuplicateLinkCount,
    ags.PostRank
FROM AggregatedPostStats ags
LEFT JOIN RankedPostEdits rpe ON ags.PostId = rpe.PostId AND rpe.rn = 1
WHERE ags.Score > 0

UNION ALL

SELECT
    ags.PostId,
    ags.PostTypeName,
    ags.OwnerDisplayName,
    ags.PostCreationDate,
    ags.Score,
    ags.ViewCount,
    ags.InteractionCount,
    ags.DaysToClose,
    ags.FormattedTags,
    ags.FirstTag,
    rpe.EditorDisplayName AS LastEditorDisplayName,
    rpe.CreationDate AS LastEditDate,
    ags.UpVotes,
    ags.DownVotes,
    COALESCE(ags.Score, 0) * (ags.UpVotes - ags.DownVotes) AS WeightedScore,
    CASE
        WHEN ags.PostTypeName = 'Question' AND ags.AnswerCount > 0 THEN CAST(ags.Score AS DOUBLE PRECISION) / ags.AnswerCount
        ELSE NULL
    END AS ScorePerAnswer,
    CASE
        WHEN ags.PostTypeName = 'Question' THEN
            (SELECT COUNT(*)
             FROM PostLinks pl
             WHERE pl.PostId = ags.PostId AND pl.LinkTypeId = 3)
        ELSE NULL
    END AS DuplicateLinkCount,
    ags.PostRank
FROM AggregatedPostStats ags
LEFT JOIN RankedPostEdits rpe ON ags.PostId = rpe.PostId AND rpe.rn = 1
WHERE ags.PostTypeName = 'Answer' AND ags.Score < 0;