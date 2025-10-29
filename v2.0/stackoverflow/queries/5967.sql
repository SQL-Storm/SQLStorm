WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.FavoriteCount,
    p.CommentCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId
                       ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_type
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopQuestions AS (
  SELECT
    PRA.PostId,
    PRA.Title,
    PRA.OwnerUserId,
    PRA.LastActivityDate,
    PRA.Score,
    PRA.ViewCount,
    PRA.Tags,
    PRA.CommentCount,
    PRA.Body,
    PRA.ContentLicense,
    PRA.ParentId,
    PRA.AcceptedAnswerId
  FROM RecentActivePosts PRA
  WHERE PRA.PostTypeId = 1 AND PRA.rn_type <= 50
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts AS pt WHERE pt.OwnerUserId = u.Id) AS PostsOwned,
    (SELECT COUNT(*) FROM Comments AS c WHERE c.UserId = u.Id) AS CommentsMade,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.UserId = u.Id) AS VotesCast
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
-- normalize tags into rows using a set-returning construct in its own CTE to avoid using it in JOIN conditions
PostTags AS (
  SELECT
    p.PostId,
    TRIM(tag) AS TagName
  FROM TopQuestions p,
  LATERAL (
    SELECT regexp_split_to_table(
             substring(p.Tags FROM 2 FOR char_length(p.Tags)-2),
             '><'
           ) AS tag
  ) st
),
TagStats AS (
  SELECT
    pt.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS SumViews
  FROM PostTags pt
  JOIN TopQuestions p ON p.PostId = pt.PostId
  GROUP BY pt.TagName
),
Combined AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerUserId,
    ua.UserId AS QueriedUserId,
    ua.DisplayName AS QueriedName,
    tq.LastActivityDate,
    tq.Score,
    tq.ViewCount,
    tq.Body,
    tq.Tags,
    tq.ContentLicense,
    COALESCE(ts.TagPostCount, 0) AS RelatedTagPostCount,
    COALESCE(ts.AvgScore, 0) AS RelatedTagAvgScore,
    COALESCE(ts.SumViews, 0) AS RelatedTagSumViews
  FROM TopQuestions tq
  LEFT JOIN UserActivity ua ON tq.OwnerUserId = ua.UserId
  LEFT JOIN PostTags pt ON pt.PostId = tq.PostId
  LEFT JOIN TagStats ts ON pt.TagName = ts.TagName
),
Agg AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.QueriedUserId,
    c.QueriedName,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Body,
    c.Tags,
    c.ContentLicense,
    c.RelatedTagPostCount,
    c.RelatedTagAvgScore,
    c.RelatedTagSumViews,
    (c.Score * 1.0) / NULLIF(c.ViewCount,0) AS ScorePerView,
    CASE
      WHEN c.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days' THEN 1
      ELSE 0
    END AS ActiveLast7d,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 2) AS UpModCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 3) AS DownModCount
  FROM Combined c
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId,
  a.QueriedUserId,
  a.QueriedName,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.ScorePerView,
  a.ActiveLast7d,
  a.Body,
  a.Tags,
  a.ContentLicense,
  a.RelatedTagPostCount,
  a.RelatedTagAvgScore,
  a.RelatedTagSumViews,
  a.UpModCount,
  a.DownModCount
FROM Agg a
ORDER BY a.LastActivityDate DESC, a.Score DESC
LIMIT 100;