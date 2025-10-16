-- {"query": "6043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1105} 
WITH
-- recent activity per user with ranking
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(MAX(p.LastActivityDate), u.LastAccessDate) AS LastActive,
    COUNT(DISTINCT p.Id) AS PostsCount,
    SUM(CASE WHEN v.VoteTypeId IN (2,6,9,10) THEN 1 ELSE 0 END) AS NegativeVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- top tags by activity in questions
TopTagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    SUM(p.Score) AS ScoreSum,
    STRING_AGG(DISTINCT t.TagName, ',') WITHIN GROUP (ORDER BY t.TagName) AS TagList
  FROM Posts ps
  JOIN LATERAL (
    SELECT UNNEST(string_to_array(substring(ps.Tags, 2, length(ps.Tags)-2), '><')) AS TagName
  ) AS t ON true
  JOIN Tags tg ON tg.TagName = t.TagName
  JOIN Posts p ON p.Id = ps.Id
  WHERE ps.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY ScoreSum DESC
  LIMIT 5
),
-- correlated subquery: posts with many revisions and their editors
PostRevisionInfo AS (
  SELECT
    ps.Id AS PostId,
    ps.Title,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = ps.Id) AS RevisionCount,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = ps.Id) AS LastRevisionDate,
    (SELECT ph.UserDisplayName FROM PostHistory ph WHERE ph.PostId = ps.Id ORDER BY ph.CreationDate DESC LIMIT 1) AS LastEditor
  FROM Posts ps
  WHERE ps.PostTypeId = 1
),
-- complex window: recent posts per user with cumulative sums
RecentPostsWindow AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate > (CURRENT_DATE - INTERVAL '365 days')
),
-- set operation: union of top questions and high-view posts
UnionSet AS (
  SELECT PostId, Title, CreationDate, Score, ViewCount, OwnerUserId
  FROM Posts
  WHERE PostTypeId = 1
  ORDER BY Score DESC
  LIMIT 100
  UNION ALL
  SELECT rp.PostId, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerUserId
  FROM RecentPostsWindow rp
  WHERE rp.rn <= 50
),
-- outer join example: posts with missing tags and their summaries
PostsWithTags AS (
  SELECT
    ps.Id AS PostId,
    ps.Title,
    t.TagName,
    t.Count AS TagCount
  FROM Posts ps
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(ps.Tags, 2, length(ps.Tags)-2), '><')) AS TagName
  ) AS t ON true
  LEFT JOIN Tags tg ON tg.TagName = t.TagName
  WHERE ps.PostTypeId = 1
),
-- final select combining multiple constructs
FinalResult AS (
  SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.LastActive,
    au.PostsCount,
    au.NegativeVotes,
    au.UpvotesReceived,
    au.DownvotesReceived,
    tga.PostId AS TagRelatedPostId,
    tga.Title AS TagRelatedPostTitle,
    tga.TagName,
    pav.Score AS PostScore,
    pav.ViewCount AS PostViews,
    pav.CreationDate AS PostDate
  FROM UserActivity au
  LEFT JOIN LATERAL (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, tg.TagName
    FROM Posts p
    LEFT JOIN Tags tg ON tg.TagName = (
      SELECT TagName FROM Tags tg2 WHERE tg2.TagName = tg2.TagName LIMIT 1
    )
    WHERE p.OwnerUserId = au.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
  ) pav ON true
  LEFT JOIN PostsWithTags tga ON tga.PostId = pav.Id
)
SELECT *
FROM FinalResult
ORDER BY Reputation DESC, LastActive DESC
LIMIT 200;