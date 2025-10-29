WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagScore AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
CorrelatedCommentStats AS (
  SELECT
    rp.PostId,
    COUNT(c.Id) AS CommentCount,
    AVG(CASE WHEN c.UserId IS NULL THEN 0 ELSE 1 END) AS ActiveCommentRatio
  FROM RecentActivePosts rp
  LEFT JOIN Comments c ON c.PostId = rp.PostId
  GROUP BY rp.PostId
),
CrossJoinActivity AS (
  SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.LastActivityDate,
    a.OwnerUserId,
    a.Score AS PostScore,
    a.ViewCount,
    a.CommentCount AS PostCommentCount,
    a.FavoriteCount,
    t.TagName,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews,
    cc.CommentCount AS CommentCountOnPost
  FROM RecentActivePosts a
  LEFT JOIN TopTags t ON t.PostId = a.PostId
  LEFT JOIN TagScore ts ON ts.TagName = t.TagName
  LEFT JOIN CorrelatedCommentStats cc ON cc.PostId = a.PostId
  WHERE (a.Score > 0 OR a.ViewCount > 100)
),
Windowed AS (
  SELECT
    ca.PostId,
    ca.Title,
    ca.CreationDate,
    ca.LastActivityDate,
    ca.OwnerUserId,
    ca.PostScore,
    ca.ViewCount,
    ca.PostCommentCount,
    ca.FavoriteCount,
    ca.TagName,
    ca.PostCount,
    ca.AvgScore,
    ca.TotalViews,
    ca.CommentCountOnPost,
    ROW_NUMBER() OVER (
      PARTITION BY ca.OwnerUserId
      ORDER BY ca.LastActivityDate DESC
    ) AS rn
  FROM CrossJoinActivity ca
),
Filtered AS (
  SELECT *
  FROM Windowed
  WHERE rn = 1
)
SELECT
  f.PostId,
  f.Title,
  f.CreationDate,
  f.LastActivityDate,
  u.DisplayName AS OwnerDisplayName,
  f.PostScore,
  f.ViewCount,
  f.PostCommentCount,
  f.FavoriteCount,
  f.TagName,
  f.PostCount AS TagPostCount,
  f.AvgScore AS TagAvgScore,
  f.TotalViews AS TagTotalViews,
  f.CommentCountOnPost
FROM Filtered f
LEFT JOIN Users u ON u.Id = f.OwnerUserId
ORDER BY f.LastActivityDate DESC
LIMIT 200;