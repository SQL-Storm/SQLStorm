WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.Comment AS EditComment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserEditSummary AS (
    SELECT
      rpe.UserId,
      COUNT(rpe.PostId) AS TotalEdits,
      MAX(rpe.EditDate) AS LastEditDate,
      STRING_AGG(DISTINCT SUBSTRING(p.Title FROM 1 FOR 50), ', ') AS SampleTitlesEdited
    FROM RankedPostEdits rpe
    JOIN Posts p
      ON rpe.PostId = p.Id
    WHERE rpe.rn = 1
    GROUP BY
      rpe.UserId
    HAVING
      COUNT(rpe.PostId) > 5
  ),
  TopUsers AS (
    SELECT
      ues.UserId,
      u.DisplayName,
      ues.TotalEdits,
      ues.LastEditDate,
      ues.SampleTitlesEdited,
      RANK() OVER (ORDER BY ues.TotalEdits DESC) AS UserRank
    FROM UserEditSummary ues
    JOIN Users u
      ON ues.UserId = u.Id
  ),
  PostCommentCount AS (
    SELECT
      p.Id AS PostId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    GROUP BY
      p.Id
  )
SELECT
  t.UserRank,
  t.DisplayName,
  t.TotalEdits,
  t.LastEditDate,
  t.SampleTitlesEdited,
  pcc.PostId,
  pcc.CommentCount,
  pcc.TotalCommentScore,
  pcc.AvgCommentScore,
  pcc.LastCommentDate,
  CASE
    WHEN pcc.CommentCount > 100 THEN 'High'
    WHEN pcc.CommentCount BETWEEN 50 AND 100 THEN 'Medium'
    ELSE 'Low'
  END AS CommentVolumeCategory,
  CASE
    WHEN pcc.AvgCommentScore > 5 THEN 'Positive'
    WHEN pcc.AvgCommentScore < 0 THEN 'Negative'
    ELSE 'Neutral'
  END AS SentimentCategory,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = pcc.PostId AND pl.LinkTypeId = 1
  ) AS LinkedPostsCount,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.RelatedPostId = pcc.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinksCount,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  p.ViewCount,
  p.Score AS PostScore,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  UPPER(pt.Name) AS PostType,
  CASE
    WHEN p.OwnerUserId = -1 THEN 'Community'
    ELSE COALESCE(u.DisplayName, 'Unknown')
  END AS OwnerDisplayName,
  p.Title,
  LENGTH(p.Body) AS BodyLength,
  CASE
    WHEN p.Tags IS NOT NULL AND POSITION('>' IN p.Tags) > 0 THEN
      SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))
    ELSE NULL
  END AS FirstTag,
  CASE
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS IsCommunityOwned
FROM TopUsers t
LEFT JOIN Posts p
  ON t.UserId = p.OwnerUserId
LEFT JOIN PostCommentCount pcc
  ON p.Id = pcc.PostId
LEFT JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
WHERE
  p.CreationDate >= DATE '2023-01-01' AND p.PostTypeId = 1
ORDER BY
  t.UserRank,
  pcc.TotalCommentScore DESC;