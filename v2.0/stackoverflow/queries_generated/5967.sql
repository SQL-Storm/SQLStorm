-- {"query": "5967.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 991} 
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
    -- window: rank posts by activity per 30d window
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId
                       ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_type
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
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
TagStats AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS SumViews
  FROM TopQuestions p
  GROUP BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
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
  LEFT JOIN TagStats ts ON unnest(string_to_array(substring(tq.Tags, 2, length(tq.Tags)-2), '><')) = ts.TagName
),
Agg AS (
  SELECT
    PostId,
    Title,
    OwnerUserId,
    QueriedUserId,
    QueriedName,
    LastActivityDate,
    Score,
    ViewCount,
    Body,
    Tags,
    ContentLicense,
    RelatedTagPostCount,
    RelatedTagAvgScore,
    RelatedTagSumViews,
    -- complex derived metrics
    (Score * 1.0) / NULLIF(ViewCount,0) AS ScorePerView,
    CASE
      WHEN LastActivityDate > NOW() - INTERVAL '7 days' THEN 1
      ELSE 0
    END AS ActiveLast7d,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = PostId AND v.VoteTypeId = 2) AS UpModCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = PostId AND v.VoteTypeId = 3) AS DownModCount
  FROM Combined
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