-- {"query": "5932.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 733} 
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
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM RecentActivePosts rap
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rap.Tags, 2, length(rap.Tags)-2), '><')) AS TagName
  ) t
  GROUP BY t.TagName
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
    vp.PostId,
    COUNT(c.Id) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Posts vp
  LEFT JOIN Comments c ON c.PostId = vp.Id
  GROUP BY vp.PostId
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
    ta.TagName,
    ta.TotalScore AS TagTotalScore,
    ta.AvgViews AS TagAvgViews,
    ta.PostCount AS TagPostCount,
    ui.UserId,
    ui.DisplayName AS UserDisplayName,
    ui.PostsCreated,
    ui.TotalScoreFromPosts,
    ui.TotalViews,
    ca.CommentCount,
    ca.LastCommentDate
  FROM RecentActivePosts rap
  LEFT JOIN TopTags ta
    ON ta.TagName = ANY(string_to_array(substring(rap.Tags, 2, length(rap.Tags)-2), '><'))
  LEFT JOIN UserImpact ui
    ON ui.UserId = rap.OwnerUserId
  LEFT JOIN CommentActivity ca
    ON ca.PostId = rap.Id
)
SELECT
  PostId,
  Title,
  PostTypeId,
  OwnerUserId,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  Tags,
  COALESCE(TagName, 'untagged') AS TopAssociatedTag,
  COALESCE(TagTotalScore, 0) AS TopTagTotalScore,
  COALESCE(TagAvgViews, 0) AS TopTagAvgViews,
  COALESCE(TagPostCount, 0) AS TopTagPostCount,
  UserId,
  UserDisplayName,
  PostsCreated,
  TotalScoreFromPosts,
  TotalViews,
  CommentCount,
  LastCommentDate
FROM Final
WHERE
  COALESCE(TagPostCount, 0) > 0
  OR rap.OwnerUserId IS NOT NULL
ORDER BY LastActivityDate DESC
LIMIT 200;