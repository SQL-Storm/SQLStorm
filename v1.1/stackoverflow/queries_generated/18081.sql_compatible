WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByUser,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalScoreByUser,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        CASE
            WHEN p.FavoriteCount > 100 AND p.ViewCount > 1000 THEN 'Popular'
            WHEN p.Score > 50 THEN 'Highly Rated'
            ELSE 'Standard'
        END AS PostCategory
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(u.LastAccessDate) AS LastAccess
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id
),
PopularTags AS (
    SELECT
        SUBSTRING(tag, 2, LENGTH(tag) - 2) AS TagName,
        COUNT(p.Id) AS PostCount
    FROM Posts p,
         LATERAL (
           SELECT regexp_split_to_table(p.Tags, '><') AS tag
         ) s
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH
    GROUP BY SUBSTRING(tag, 2, LENGTH(tag) - 2)
    HAVING COUNT(p.Id) > 500
)
SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PostCategory,
    phs.EditCount,
    phs.LastEditDate,
    ue.CommentCount AS UserComments,
    ue.VoteCount AS UserVotes,
    ue.LastAccess AS UserLastAccess,
    CASE WHEN rp.Score > 0 THEN CAST(rp.Score AS NUMERIC(10,2)) / rp.ViewCount ELSE 0 END AS ScoreToViewRatio,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.AnswerCount = 0 AND rp.Score < 0 THEN 'Unanswered/Negative'
        WHEN rp.AnswerCount > 5 AND rp.Score > 20 THEN 'High Answer Count & Score'
        ELSE 'Standard Content'
    END AS PostStatus,
    CASE
        WHEN pt.TagName IN (SELECT TagName FROM PopularTags) THEN 'Popular Tag'
        ELSE 'Other Tag'
    END AS TagPopularity,
    (rp.PreviousPostScore + rp.NextPostScore) / 2.0 AS AvgNeighborScore
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN Posts p_tags ON rp.PostId = p_tags.Id
LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(p_tags.Tags, '><') AS tag
) tag_split ON true
LEFT JOIN Tags pt ON SUBSTRING(tag_split.tag, 2, LENGTH(tag_split.tag) - 2) = pt.TagName
WHERE rp.RowNumByUser <= 10
  AND rp.ScoreRank BETWEEN 100 AND 200
  AND rp.TotalScoreByUser > 1000
  AND rp.PostCategory = 'Popular'
  AND COALESCE(rp.OwnerDisplayName, 'Deleted User') <> 'Deleted User'
GROUP BY
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PostCategory,
    phs.EditCount,
    phs.LastEditDate,
    ue.CommentCount,
    ue.VoteCount,
    ue.LastAccess,
    rp.PreviousPostScore,
    rp.NextPostScore,
    pt.TagName
HAVING MAX(CASE WHEN pt.TagName IN (SELECT TagName FROM PopularTags) THEN 1 ELSE 0 END) = 1
ORDER BY rp.Score DESC;