WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Body,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.LastEditDate,
    p.LastEditorUserId,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
Engagement AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.LastActivityDate,
    rp.Reputation,
    rp.DisplayName,
    rp.Location,
    rp.AccountId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId IN (2,3)) AS UpDownVotes,
    AVG(rp.Score) OVER (
      PARTITION BY rp.PostTypeId
      ORDER BY rp.CreationDate
      ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS ScoreMovingAvg
  FROM RankedPosts rp
  WHERE rp.rn_by_type = 1
),
Qualified AS (
  SELECT
    e.PostId,
    e.PostTypeId,
    e.OwnerUserId,
    e.CreationDate,
    e.Title,
    e.ViewCount,
    e.Score,
    e.LastActivityDate,
    e.Reputation,
    e.DisplayName,
    e.Location,
    e.AccountId,
    e.CommentCount,
    e.UpDownVotes,
    e.ScoreMovingAvg,
    CASE
      WHEN e.ViewCount > 1000 AND e.Score > 5 THEN 'Popular_QA'
      WHEN e.ViewCount > 5000 THEN 'Trending'
      ELSE 'Standard'
    END AS Category
  FROM Engagement e
  WHERE e.CommentCount >= 2
     OR e.UpDownVotes >= 5
),
CrossLinks AS (
  SELECT
    q.PostId,
    q.Title,
    q.Category,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId
  FROM Qualified q
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
TagSignal AS (
  SELECT
    cl.PostId,
    cl.Title,
    cl.Category,
    cl.LinkTypeName,
    (
      SELECT STRING_AGG(t.TagName, ',') FROM (
        SELECT TRIM(x.value) AS TagName
        FROM UNNEST(STRING_TO_ARRAY(cl.Title, ' ')) AS x(value)
        WHERE x.value ~ '\\w{4,}'
      ) t
    ) AS TokenTags,
    -- bring through other needed columns for final grouping/selection
    (SELECT p2.CreationDate FROM Posts p2 WHERE p2.Id = cl.PostId LIMIT 1) AS CreationDate,
    (SELECT p3.OwnerUserId FROM Posts p3 WHERE p3.Id = cl.PostId LIMIT 1) AS OwnerUserId,
    cl.PostId AS PostId_for_grp,
    cl.Category AS Category_for_grp,
    cl.LinkTypeName AS LinkTypeName_for_grp
  FROM CrossLinks cl
)
SELECT
  ts.PostId,
  ts.Title,
  ts.Category,
  ts.LinkTypeName,
  ts.TokenTags,
  ls.Reputation,
  ls.DisplayName,
  ls.Location,
  ts.CreationDate AS CreationDate,
  ts_score.ScoreMovingAvg AS MovingAvgScore,
  ts_view.ViewCount,
  ts_comment.CommentCount
FROM TagSignal ts
LEFT JOIN Users ls ON ls.Id = ts.OwnerUserId
LEFT JOIN LATERAL (
  SELECT AVG(e.Score) AS ScoreMovingAvg
  FROM Engagement e
  WHERE e.PostId = ts.PostId
) ts_score ON TRUE
LEFT JOIN LATERAL (
  SELECT e.ViewCount, e.CommentCount
  FROM Engagement e
  WHERE e.PostId = ts.PostId
  LIMIT 1
) ts_view_comment ON TRUE
LEFT JOIN LATERAL (
  SELECT e.ViewCount
  FROM Engagement e
  WHERE e.PostId = ts.PostId
  LIMIT 1
) ts_view ON TRUE
LEFT JOIN LATERAL (
  SELECT e.CommentCount
  FROM Engagement e
  WHERE e.PostId = ts.PostId
  LIMIT 1
) ts_comment ON TRUE
GROUP BY
  ts.PostId,
  ts.Title,
  ts.Category,
  ts.LinkTypeName,
  ts.TokenTags,
  ls.Reputation,
  ls.DisplayName,
  ls.Location,
  ts.CreationDate,
  ts_score.ScoreMovingAvg,
  ts_view.ViewCount,
  ts_comment.CommentCount
ORDER BY ts.Category, ts_score.ScoreMovingAvg DESC
LIMIT 100;