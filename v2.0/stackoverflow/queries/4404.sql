WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    pt.Name AS PostTypeName,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
    SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore
  FROM Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  WHERE
    p.Score > 5 AND p.CreationDate > DATE '2023-01-01'
), PostInteractionSummary AS (
  SELECT
    p.Id,
    COUNT(c.Id) AS CommentCount,
    COUNT(DISTINCT v.UserId) AS DistinctVoterCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  GROUP BY
    p.Id
)
SELECT
  rp.PostId,
  rp.PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount AS PostHistoryCommentCount,
  pis.CommentCount AS ActualCommentCount,
  pis.UpVoteCount,
  pis.DownVoteCount,
  (rp.Score - pis.UpVoteCount + pis.DownVoteCount) AS NetScoreCalculation,
  CASE
    WHEN rp.ScoreRank <= 5 THEN 'Top 5 in Type'
    WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'High Score & High Answers'
    ELSE 'Standard Post'
  END AS PostCategory,
  CASE
    WHEN u.Reputation > 10000 THEN 'High Reputation User'
    WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation User'
    ELSE 'Low Reputation User'
  END AS UserReputationLevel,
  SUBSTRING(rp.PostTypeName FROM 1 FOR 3) AS PostTypePrefix,
  rp.ScoreRank,
  rp.CumulativeScore,
  ph.Comment AS LastEditComment,
  CASE
    WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
    WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 'ModerationAction'
    ELSE 'Other'
  END AS LastActionType
FROM RankedPosts rp
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
LEFT JOIN PostInteractionSummary pis
  ON rp.PostId = pis.Id
LEFT JOIN PostHistory ph
  ON rp.PostId = ph.PostId AND ph.CreationDate = (
    SELECT
      MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE
      ph2.PostId = rp.PostId AND ph2.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15)
  )
WHERE
  rp.Score > 0 OR rp.AnswerCount > 0

UNION ALL

SELECT
  p.Id AS PostId,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS PostHistoryCommentCount,
  NULL AS ActualCommentCount,
  NULL AS UpVoteCount,
  NULL AS DownVoteCount,
  NULL AS NetScoreCalculation,
  NULL AS PostCategory,
  NULL AS UserReputationLevel,
  NULL AS PostTypePrefix,
  NULL AS ScoreRank,
  NULL AS CumulativeScore,
  NULL AS LastEditComment,
  NULL AS LastActionType
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
WHERE
  p.Score < 0 AND p.CreationDate > DATE '2023-01-01'
ORDER BY
  Score DESC NULLS LAST,
  CreationDate DESC;