WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestPostEdits AS (
    SELECT
      PostId,
      UserId,
      CreationDate,
      PostHistoryTypeId,
      Comment
    FROM
      RankedPostEdits
    WHERE
      rn = 1
  ),
  UserPostInteraction AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(p.ViewCount) AS MaxViewCount
    FROM
      Posts p
      LEFT JOIN Comments c ON p.Id = c.PostId
      LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate
  )
SELECT
  p.Id AS PostId,
  p.Title,
  p.Tags,
  p.Score,
  p.AnswerCount,
  p.FavoriteCount,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  p.ClosedDate,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(lp.CreationDate, p.CreationDate) AS LastEditOrCreationDate,
  COALESCE(lp.UserId, p.OwnerUserId) AS LastEditorOrOwnerId,
  COALESCE(lp.Comment, 'No Edits') AS LastEditComment,
  upi.CommentCount,
  upi.UpVoteCount,
  upi.DownVoteCount,
  upi.MaxViewCount,
  CASE
    WHEN p.FavoriteCount > 50 AND p.AnswerCount > 10 AND upi.UpVoteCount > 100 THEN 'Highly Engaged'
    WHEN p.Score < 0 THEN 'Negative Score'
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Standard'
  END AS PostStatusCategory,
  LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
  SUM(upi.UpVoteCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpvotes
FROM
  Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN LatestPostEdits lp ON p.Id = lp.PostId
  LEFT JOIN UserPostInteraction upi ON p.Id = upi.PostId
WHERE
  p.PostTypeId = 1
  AND p.CreationDate >= DATE '2023-01-01'
  AND (
    p.Score > 0
    OR p.AnswerCount > 0
    OR upi.UpVoteCount > 0
  )
  AND LOWER(p.Title) LIKE '%sql%'
  OR EXISTS (
    SELECT
      1
    FROM
      Tags t
    WHERE
      t.TagName = 'performance' AND t.Id IN (SELECT Id FROM Posts WHERE Id = p.Id)
  )
UNION ALL
SELECT
  NULL AS PostId,
  'No Matching Questions' AS Title,
  NULL AS Tags,
  NULL AS Score,
  NULL AS AnswerCount,
  NULL AS FavoriteCount,
  NULL AS PostCreationDate,
  NULL AS LastActivityDate,
  NULL AS ClosedDate,
  NULL AS OwnerDisplayName,
  NULL AS LastEditOrCreationDate,
  NULL AS LastEditorOrOwnerId,
  NULL AS LastEditComment,
  0 AS CommentCount,
  0 AS UpVoteCount,
  0 AS DownVoteCount,
  0 AS MaxViewCount,
  'No Data' AS PostStatusCategory,
  0 AS PreviousPostScore,
  0 AS CumulativeUpvotes
FROM
  (SELECT 1) AS dual
WHERE
  NOT EXISTS (
    SELECT
      1
    FROM
      Posts p
      INNER JOIN Users u ON p.OwnerUserId = u.Id
      LEFT JOIN LatestPostEdits lp ON p.Id = lp.PostId
      LEFT JOIN UserPostInteraction upi ON p.Id = upi.PostId
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE '2023-01-01'
      AND (p.Score > 0 OR p.AnswerCount > 0 OR upi.UpVoteCount > 0)
      AND LOWER(p.Title) LIKE '%sql%'
  );