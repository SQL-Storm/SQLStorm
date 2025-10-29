WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY
),
-- split tags into rows using a set-returning approach compatible with many engines:
TagSplits AS (
  SELECT
    rap.Id AS PostId,
    trim(tag) AS TagName
  FROM RecentActivePosts rap,
  LATERAL (
    SELECT regexp_split_to_table(
      substring(rap.Tags FROM 2 FOR (char_length(rap.Tags) - 2)),
      '><'
    ) AS tag
  ) s
),
TopTags AS (
  SELECT
    ts.TagName,
    SUM(rap.Score) AS TotalScore,
    AVG(rap.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM RecentActivePosts rap
  JOIN TagSplits ts ON ts.PostId = rap.Id
  GROUP BY ts.TagName
),
UserImpact AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsCreated,
    SUM(p.Score) AS TotalScoreFromPosts,
    SUM(p.ViewCount) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName
),
CommentActivity AS (
  SELECT
    vp.Id AS PostId,
    COUNT(c.Id) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Posts vp
  LEFT JOIN Comments c ON c.PostId = vp.Id
  GROUP BY vp.Id
),
Final AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    tt.TagName,
    tt.TotalScore AS TagTotalScore,
    tt.AvgViews AS TagAvgViews,
    tt.PostCount AS TagPostCount,
    ui.UserId,
    ui.DisplayName AS UserDisplayName,
    ui.PostsCreated,
    ui.TotalScoreFromPosts,
    ui.TotalViews,
    ca.CommentCount,
    ca.LastCommentDate
  FROM RecentActivePosts rap
  LEFT JOIN (
    -- choose one representative tag per post by joining TagSplits -> TopTags; this avoids non-inner join on subquery issues
    SELECT ts.PostId, tt.TagName, tt.TotalScore, tt.AvgViews, tt.PostCount
    FROM TagSplits ts
    JOIN TopTags tt ON tt.TagName = ts.TagName
  ) tt ON tt.PostId = rap.Id
  LEFT JOIN UserImpact ui
    ON ui.UserId = rap.OwnerUserId
  LEFT JOIN CommentActivity ca
    ON ca.PostId = rap.Id
)
SELECT
  f.PostId,
  f.Title,
  f.PostTypeId,
  f.OwnerUserId,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.Tags,
  COALESCE(f.TagName, 'untagged') AS TopAssociatedTag,
  COALESCE(f.TagTotalScore, 0) AS TopTagTotalScore,
  COALESCE(f.TagAvgViews, 0) AS TopTagAvgViews,
  COALESCE(f.TagPostCount, 0) AS TopTagPostCount,
  f.UserId,
  f.UserDisplayName,
  f.PostsCreated,
  f.TotalScoreFromPosts,
  f.TotalViews,
  f.CommentCount,
  f.LastCommentDate
FROM Final f
WHERE
  COALESCE(f.TagPostCount, 0) > 0
  OR f.OwnerUserId IS NOT NULL
ORDER BY f.LastActivityDate DESC
LIMIT 200;