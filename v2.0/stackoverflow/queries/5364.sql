-- {"query": "5364.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 977}
WITH recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
),
popular_tags AS (
  SELECT
    tag
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
    FROM Posts p
    JOIN recent_posts rp ON rp.PostId = p.Id
    WHERE p.Tags IS NOT NULL
  ) t
  GROUP BY tag
  HAVING COUNT(*) > 5
),
tag_summary AS (
  SELECT
    t.tag AS TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM popular_tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.tag || '%'
  GROUP BY t.tag
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.WebsiteUrl,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
user_activity AS (
  SELECT
    t.UserId,
    COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    COUNT(P.Id) AS PostsCreated
  FROM top_users t
  LEFT JOIN Posts P ON P.OwnerUserId = t.UserId
  LEFT JOIN Votes V ON V.PostId = P.Id
  GROUP BY t.UserId
),
complex_calcs AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    CASE
      WHEN rp.Score > 0 THEN 'Positive'
      WHEN rp.Score < 0 THEN 'Negative'
      ELSE 'Neutral'
    END AS ScoreSentiment,
    CASE
      WHEN rp.ViewCount > 1000 THEN 'Hot'
      WHEN rp.ViewCount > 100 AND rp.ViewCount <= 1000 THEN 'Warm'
      ELSE 'Cold'
    END AS ViewTier,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = rp.Id) AS LastRevisionDate,
    rp.OwnerUserId
  FROM Posts rp
  WHERE rp.PostTypeId = 1
),
outer_join_demo AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.ViewCount,
    cp.Score,
    cp.OwnerUserId,
    u.DisplayName AS OwnerName,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    ua.UpvotesGiven,
    ua.DownvotesGiven,
    ua.PostsCreated,
    cp.LastRevisionDate
  FROM complex_calcs cp
  LEFT JOIN Users u ON u.Id = cp.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = cp.OwnerUserId
  LEFT JOIN user_activity ua ON ua.UserId = cp.OwnerUserId
)
SELECT
  tp.TagName,
  tp.PostCount,
  tp.AvgScore,
  tp.TotalViews,
  tp.LastActive,
  tu.UserId,
  tu.DisplayName AS TopUserName,
  tu.Reputation AS TopUserReputation,
  tu.LastAccessDate,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  ua.PostsCreated,
  oc.PostId,
  oc.Title AS PostTitle,
  oc.ViewCount AS PostViews,
  oc.Score AS PostScore,
  oc.LastRevisionDate
FROM tag_summary tp
LEFT JOIN (
  SELECT * FROM top_users WHERE rn <= 5
) tu ON TRUE
LEFT JOIN user_activity ua ON ua.UserId = tu.UserId
LEFT JOIN outer_join_demo oc ON oc.OwnerUserId = tu.UserId
GROUP BY
  tp.TagName,
  tp.PostCount,
  tp.AvgScore,
  tp.TotalViews,
  tp.LastActive,
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.LastAccessDate,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  ua.PostsCreated,
  oc.PostId,
  oc.Title,
  oc.ViewCount,
  oc.Score,
  oc.LastRevisionDate
ORDER BY tp.PostCount DESC, tp.TotalViews DESC
LIMIT 100;