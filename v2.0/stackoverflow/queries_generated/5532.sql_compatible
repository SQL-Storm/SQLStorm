WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TagEngagement AS (
  SELECT
    tag.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
  ) AS tag
  WHERE p.PostTypeId = 1
  GROUP BY tag.TagName
),
FilteredUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe
  FROM Users u
  WHERE u.Reputation >= 1000
),
CrossJoinSample AS (
  SELECT
    q.PostId,
    q.Title,
    q.ViewCount,
    q.Score,
    q.CreationDate,
    q.OwnerUserId,
    q.LastActivityDate,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    u.Id AS RespondentUserId,
    u.DisplayName AS RespondentName,
    v.CreationDate AS VoteDate,
    v.VoteTypeId
  FROM RecentTopQuestions q
  LEFT JOIN Votes v ON v.PostId = q.PostId AND v.VoteTypeId = 2
  LEFT JOIN FilteredUsers u ON u.Id = q.OwnerUserId
  WHERE q.rn <= 200
),
ComplexFilters AS (
  SELECT
    c.PostId,
    c.Title,
    c.ViewCount,
    c.Score,
    c.CreationDate,
    c.OwnerUserId,
    c.LastActivityDate,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    CASE
      WHEN c.ViewCount > 1000 THEN 'HighView'
      WHEN c.ViewCount BETWEEN 100 AND 1000 THEN 'MedView'
      ELSE 'LowView'
    END AS ViewTier,
    CONCAT_WS(' | ', COALESCE(u.DisplayName, ''), COALESCE(p.Title, '')) AS DerivedLabel
  FROM CrossJoinSample c
  LEFT JOIN Users u ON u.Id = c.OwnerUserId
  LEFT JOIN Posts p ON p.Id = c.PostId
  WHERE c.Score > 0
    AND (c.FavoriteCount IS NULL OR c.FavoriteCount >= 1)
  GROUP BY
    c.PostId,
    c.Title,
    c.ViewCount,
    c.Score,
    c.CreationDate,
    c.OwnerUserId,
    c.LastActivityDate,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    u.DisplayName,
    p.Title
),
Windowed AS (
  SELECT
    v.PostId,
    v.CreationDate AS VoteDate,
    v.VoteTypeId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS UpvotesLast30,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS UpvoteRateLast30
  FROM Votes v
  WHERE v.PostId IN (SELECT PostId FROM ComplexFilters)
),
Final AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.ViewCount,
    cf.Score,
    cf.CreationDate,
    cf.OwnerUserId,
    cf.LastActivityDate,
    cf.CommentCount,
    cf.AnswerCount,
    cf.FavoriteCount,
    cf.ViewTier,
    cf.DerivedLabel,
    w.UpvotesLast30,
    w.UpvoteRateLast30
  FROM ComplexFilters cf
  LEFT JOIN Windowed w ON w.PostId = cf.PostId
)
SELECT
  f.PostId,
  f.Title,
  f.ViewCount,
  f.Score,
  f.CreationDate,
  f.OwnerUserId,
  (SELECT u.DisplayName FROM Users u WHERE u.Id = f.OwnerUserId) AS OwnerDisplayName,
  f.LastActivityDate,
  f.CommentCount,
  f.AnswerCount,
  f.FavoriteCount,
  f.ViewTier,
  f.DerivedLabel,
  f.UpvotesLast30,
  f.UpvoteRateLast30
FROM Final f
ORDER BY f.ViewCount DESC, f.Score DESC
LIMIT 100;