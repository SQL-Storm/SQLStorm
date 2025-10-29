WITH PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN CAST('2024-10-01 12:34:56' AS timestamp) - p.ClosedDate
            ELSE NULL
        END AS DaysSinceClosed,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_by_score,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
CommentMetrics AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
VoteDistribution AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoriteVoteCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY v.PostId
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.OwnerDisplayName,
    pd.PostCreationDate,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCount AS PostCommentCount,
    pd.FavoriteCount AS PostFavoriteCount,
    cm.CommentCount AS TotalComments,
    cm.TotalCommentScore AS TotalCommentScore,
    cm.AvgCommentScore AS AvgCommentScore,
    vd.UpVoteCount,
    vd.DownVoteCount,
    vd.FavoriteVoteCount,
    pd.DaysSinceClosed,
    pd.rn_by_score,
    pd.avg_score_by_type,
    CASE
        WHEN pd.Score > pd.avg_score_by_type * 1.5 THEN 'HighScoring'
        WHEN pd.Score < pd.avg_score_by_type * 0.5 THEN 'LowScoring'
        ELSE 'AverageScoring'
    END AS ScoreCategory,
    LOWER(SUBSTRING(pd.OwnerDisplayName FROM 1 FOR 3)) AS FirstThreeCharsDisplayName,
    CASE WHEN pd.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status,
    CASE
        WHEN pd.OwnerDisplayName IS NULL THEN 'AnonymousOwner'
        ELSE 'NamedOwner'
    END AS OwnerType,
    UPPER(pt.Name) AS POST_TYPE_UPPER,
    COALESCE(cm.LastCommentDate, pd.PostCreationDate) AS LatestActivityDate,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pd.PostId AND pl.LinkTypeId = 3) THEN 'HasDuplicateLink'
        ELSE 'NoDuplicateLink'
    END AS DuplicateLinkStatus
FROM PostDetails pd
LEFT JOIN CommentMetrics cm ON pd.PostId = cm.PostId
LEFT JOIN VoteDistribution vd ON pd.PostId = vd.PostId
LEFT JOIN PostTypes pt ON pd.PostTypeId = pt.Id
WHERE pd.rn_by_score <= 100
  AND pd.ViewCount > 1000
  AND (pd.Score > 50 OR pd.AnswerCount > 10)
ORDER BY pd.PostTypeId, pd.Score DESC;