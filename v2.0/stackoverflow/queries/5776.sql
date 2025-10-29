WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_owner
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
Activity AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    t.OwnerUserId,
    t.LastActivityDate,
    t.CommentCount,
    t.AnswerCount,
    t.FavoriteCount,
    t.ContentLicense,
    t.Reputation,
    t.OwnerDisplayName,
    t.AccountId,
    -CASE WHEN t.Reputation IS NULL THEN 0 ELSE 1 END AS HasOwner,
    MAX(t.Score) OVER (PARTITION BY tg.TagName ORDER BY t.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS MovingMaxScore
  FROM TopQuestions t
  LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(
      -- normalize tag string like "<tag1><tag2>" into rows
      TRIM(BOTH '<>' FROM t.Tags) -- if t.Tags is null this becomes null; function behavior based on dialect
    , '>><<') AS TagName
  ) tg ON true
),
CorrelatedTags AS (
  SELECT
    a.PostId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.LastActivityDate,
    a.CommentCount,
    a.AnswerCount,
    a.FavoriteCount,
    a.ContentLicense,
    a.Reputation,
    a.OwnerDisplayName,
    a.AccountId,
    a.MovingMaxScore,
    COUNT(*) OVER () AS TotalPosts
  FROM Activity a
)
SELECT
  ct.PostId,
  ct.Title,
  ct.Tags,
  ct.CreationDate,
  ct.Score,
  ct.ViewCount,
  ct.OwnerUserId,
  ct.LastActivityDate,
  ct.CommentCount,
  ct.AnswerCount,
  ct.FavoriteCount,
  ct.ContentLicense,
  ct.Reputation,
  ct.OwnerDisplayName,
  ct.AccountId,
  ct.MovingMaxScore,
  ct.TotalPosts
FROM CorrelatedTags ct
WHERE ct.MovingMaxScore IS NOT NULL
ORDER BY ct.MovingMaxScore DESC, ct.LastActivityDate DESC
LIMIT 100;