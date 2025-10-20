WITH LatestEdits AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LatestEditDate
  FROM PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6)
  GROUP BY
    ph.PostId
),
QuestionMetrics AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Score AS QuestionScore,
    p.ViewCount AS QuestionViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount AS QuestionFavoriteCount,
    p.CreationDate AS QuestionCreationDate,
    p.OwnerUserId AS QuestionOwnerUserId,
    u.DisplayName AS QuestionOwnerDisplayName,
    le.LatestEditDate,
    (
      SELECT
        COUNT(*)
      FROM Posts a
      WHERE
        a.ParentId = p.Id AND a.PostTypeId = 2
    ) AS ActualAnswerCount,
    (
      SELECT
        AVG(CAST(c.Score AS DECIMAL(10, 2)))
      FROM Comments c
      WHERE
        c.PostId = p.Id
    ) AS AverageCommentScore,
    (
      SELECT
        COUNT(DISTINCT v.UserId)
      FROM Votes v
      WHERE
        v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS UpvoteCount,
    (
      SELECT
        COUNT(DISTINCT v.UserId)
      FROM Votes v
      WHERE
        v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS DownvoteCount,
    (
      SELECT
        COUNT(*)
      FROM PostLinks pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinkCount
  FROM Posts p
  INNER JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN LatestEdits le
    ON p.Id = le.PostId
  WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  GROUP BY
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName,
    le.LatestEditDate
)
SELECT
  qm.QuestionId,
  qm.Title,
  qm.QuestionScore,
  qm.QuestionViewCount,
  qm.AnswerCount,
  qm.ActualAnswerCount,
  qm.AverageCommentScore,
  qm.UpvoteCount,
  qm.DownvoteCount,
  qm.QuestionFavoriteCount,
  qm.DuplicateLinkCount,
  qm.QuestionOwnerDisplayName,
  qm.QuestionCreationDate,
  qm.LatestEditDate,
  (qm.QuestionScore * 1.0 / NULLIF(qm.QuestionViewCount, 0)) AS ScorePerView,
  (qm.ActualAnswerCount * 1.0 / NULLIF(qm.AnswerCount, 0)) AS ActualToReportedAnswerRatio,
  (qm.UpvoteCount * 1.0 / NULLIF(qm.DownvoteCount, 0)) AS UpvoteToDownvoteRatio
FROM QuestionMetrics qm
WHERE
  qm.QuestionScore > 10
ORDER BY
  qm.QuestionViewCount DESC,
  qm.QuestionScore DESC
LIMIT 100;