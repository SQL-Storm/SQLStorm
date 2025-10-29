WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestEdits AS (
    SELECT
      rph.PostId,
      rph.UserId AS LastEditorUserId,
      rph.CreationDate AS LastEditDate,
      rph.PostHistoryTypeId
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts AS p
    GROUP BY
      p.OwnerUserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVoteCount,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVoteCount
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      vt.Name IN ('UpMod', 'DownMod')
    GROUP BY
      v.UserId
  ),
  PostContentAnalysis AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.Tags,
      CASE
        WHEN p.PostTypeId = 1 THEN LENGTH(p.Body)
        ELSE NULL
      END AS QuestionBodyLength,
      CASE
        WHEN p.PostTypeId = 2 THEN LENGTH(p.Body)
        ELSE NULL
      END AS AnswerBodyLength,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS PostStatus
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2)
  )
SELECT
  pca.PostId,
  pt.Name AS PostType,
  pca.Title,
  u.DisplayName AS OwnerDisplayName,
  pca.CreationDate,
  pca.Score,
  pca.AnswerCount,
  pca.CommentCount,
  pca.FavoriteCount,
  pca.ViewCount,
  pca.Tags,
  pca.QuestionBodyLength,
  pca.AnswerBodyLength,
  pca.PostStatus,
  COALESCE(le.LastEditorUserId, -1) AS LastEditorUserId,
  le.LastEditDate,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount AS OwnerAnswerCount,
  COALESCE(uvs.UpVoteCount, 0) AS OwnerUpVotes,
  COALESCE(uvs.DownVoteCount, 0) AS OwnerDownVotes,
  CASE
    WHEN pca.Score > 100 AND pca.AnswerCount > 10 THEN 'High Engagement'
    WHEN pca.Score < 0 THEN 'Negative Score'
    WHEN pca.FavoriteCount > 50 THEN 'Highly Favorited'
    ELSE 'Standard'
  END AS EngagementCategory,
  CASE
    WHEN p.Tags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN p.Tags LIKE '%<performance>%' THEN 'Performance Related'
    ELSE 'Other'
  END AS TagCategory,
  CASE
    WHEN pca.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') AND pca.Score < 5 THEN 'Old and Low Score'
    WHEN pca.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 month') THEN 'Recent'
    ELSE 'Mature'
  END AS PostAgeCategory,
  (
    SELECT
      SUM(c.Score)
    FROM Comments AS c
    WHERE
      c.PostId = pca.PostId
  ) AS TotalCommentScore,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = pca.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
  ) AS ModerationActions,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = pca.PostId AND pl.LinkTypeId = 3
    ) THEN 'IsDuplicateOf'
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.RelatedPostId = pca.PostId AND pl.LinkTypeId = 3
    ) THEN 'HasDuplicateLink'
    ELSE 'NoDuplicateLink'
  END AS DuplicateStatus
FROM PostContentAnalysis AS pca
JOIN PostTypes AS pt
  ON pca.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON pca.OwnerUserId = u.Id
LEFT JOIN LatestEdits AS le
  ON pca.PostId = le.PostId
LEFT JOIN UserPostCounts AS upc
  ON pca.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserVoteStats AS uvs
  ON pca.OwnerUserId = uvs.UserId
LEFT JOIN Posts AS p -- Re-aliased for tag filtering
  ON pca.PostId = p.Id
WHERE
  pca.Score > -5 -- Filtering for posts with a reasonable score range for benchmarking
  AND pca.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '3 years') -- Limiting to a recent timeframe
ORDER BY
  pca.Score DESC,
  pca.CreationDate DESC;