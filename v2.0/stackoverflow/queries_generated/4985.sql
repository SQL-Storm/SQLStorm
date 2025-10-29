-- {"query": "4985.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1176} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    JOIN Users AS u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  RecentEditors AS (
    SELECT
      PostId,
      EditorDisplayName,
      EditDate
    FROM RankedPostEdits
    WHERE
      rn = 1
  ),
  PostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.FavoriteCount,
      p.ViewCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS PostStatus,
      COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as PostRank
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    GROUP BY
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      u.DisplayName,
      p.CreationDate,
      p.Score,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate
  )
SELECT
  pi.PostId,
  pt.Name AS PostTypeName,
  pi.PostRank,
  pi.OwnerDisplayName,
  pi.PostCreationDate,
  pi.PostScore,
  pi.CommentCount,
  pi.UpVoteCount,
  pi.DownVoteCount,
  pi.FavoriteCount,
  pi.ViewCount,
  pi.PostStatus,
  re.EditorDisplayName AS LastEditorDisplayName,
  re.EditDate AS LastEditDate,
  CASE
    WHEN pi.PostScore > 100 AND pi.UpVoteCount > pi.DownVoteCount * 5 THEN 'Highly Rated'
    WHEN pi.CommentCount > 50 THEN 'Comment Heavy'
    WHEN pi.FavoriteCount > 20 THEN 'Frequently Favorited'
    ELSE 'Standard'
  END AS PostCategorization,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = pi.PostId AND ph.PostHistoryTypeId = 2
  ) AS UniqueInitialBodyEditors,
  COALESCE(
    (
      SELECT
        GROUP_CONCAT(DISTINCT v.UserId ORDER BY v.UserId SEPARATOR ',')
      FROM Votes AS v
      WHERE
        v.PostId = pi.PostId AND v.VoteTypeId = 2
    ),
    'None'
  ) AS UpvoterUserIds
FROM PostInteractions AS pi
LEFT JOIN PostTypes AS pt
  ON pi.PostTypeId = pt.Id
LEFT JOIN RecentEditors AS re
  ON pi.PostId = re.PostId
WHERE
  pi.PostScore > 0 OR pi.CommentCount > 0 OR pi.FavoriteCount > 0
UNION
SELECT
  p.Id,
  pt.Name,
  NULL,
  u.DisplayName,
  p.CreationDate,
  p.Score,
  0,
  0,
  0,
  0,
  p.ViewCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END,
  p.LastEditorDisplayName,
  p.LastEditDate,
  'No Interactions' AS PostCategorization,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId = 2
  ) AS UniqueInitialBodyEditors,
  'None' AS UpvoterUserIds
FROM Posts AS p
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.Id NOT IN (
    SELECT
      PostId
    FROM PostInteractions
  )
ORDER BY
  PostRank NULLS LAST,
  PostCreationDate DESC;
