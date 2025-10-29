-- {"query": "4496.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1190}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      MAX(u.LastAccessDate) AS LastAccess
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS PostCount,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AverageScore,
      SUM(CASE WHEN p.OwnerUserId = -1 THEN 1 ELSE 0 END) AS CommunityOwnedCount
    FROM Tags t
    JOIN Posts p
      ON p.Id = t.WikiPostId
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 50
  )
SELECT
  'Performance Analysis Report' AS ReportTitle,
  COALESCE(u.DisplayName, 'Unknown User') AS UserName,
  u.Reputation,
  ua.LastAccess,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  COALESCE(rpe.EditDate, TIMESTAMP '1970-01-01') AS LastEditDate,
  tp.TagName AS MostFrequentTag,
  tp.PostCount AS TagPostCount,
  tp.AverageScore AS TagAverageScore,
  CASE
    WHEN tp.CommunityOwnedCount > tp.PostCount / 2.0 THEN 'Heavily Community Owned'
    WHEN tp.CommunityOwnedCount > 0 THEN 'Partially Community Owned'
    ELSE 'User Owned'
  END AS TagOwnershipStatus,
  SUM(CASE WHEN c.Text LIKE '%interesting%' THEN 1 ELSE 0 END) AS InterestingCommentCount,
  COUNT(p.Id) AS TotalPosts
FROM Users u
LEFT JOIN UserActivitySummary ua
  ON u.Id = ua.UserId
LEFT JOIN RankedPostEdits rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
LEFT JOIN Posts p
  ON u.Id = p.OwnerUserId
LEFT JOIN Comments c
  ON p.Id = c.PostId
LEFT JOIN (
  SELECT
    p_inner.OwnerUserId,
    tp_inner.TagName,
    tp_inner.PostCount,
    tp_inner.AverageScore,
    tp_inner.CommunityOwnedCount,
    ROW_NUMBER() OVER (PARTITION BY p_inner.OwnerUserId ORDER BY tp_inner.PostCount DESC, tp_inner.AverageScore DESC) AS tag_rn
  FROM Posts p_inner
  JOIN Tags t_inner
    ON p_inner.Id = t_inner.WikiPostId
  JOIN TagPopularity tp_inner
    ON t_inner.TagName = tp_inner.TagName
  WHERE p_inner.PostTypeId = 1
) tp
  ON u.Id = tp.OwnerUserId AND tp.tag_rn = 1
WHERE
  u.Id > 0
  AND u.CreationDate < DATE '2023-01-01'
GROUP BY
  u.Id,
  COALESCE(u.DisplayName, 'Unknown User'),
  u.Reputation,
  ua.LastAccess,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  COALESCE(rpe.EditDate, TIMESTAMP '1970-01-01'),
  tp.TagName,
  tp.PostCount,
  tp.AverageScore,
  CASE
    WHEN tp.CommunityOwnedCount > tp.PostCount / 2.0 THEN 'Heavily Community Owned'
    WHEN tp.CommunityOwnedCount > 0 THEN 'Partially Community Owned'
    ELSE 'User Owned'
  END
HAVING
  SUM(CASE WHEN c.Text LIKE '%performance%' THEN 1 ELSE 0 END) > 2
ORDER BY
  u.Reputation DESC,
  ua.LastAccess ASC
LIMIT 100;