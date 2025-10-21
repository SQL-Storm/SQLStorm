-- {"query": "364.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25399} 
WITH
user_posts AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) AS PostCount,
         SUM(p.Score) AS PostScore,
         MAX(p.LastActivityDate) AS LastActivityDate
  FROM Posts p
  WHERE p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),
user_votes_cast AS (
  SELECT v.UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast
  FROM Votes v
  GROUP BY v.UserId
),
user_votes_received AS (
  SELECT p.OwnerUserId AS UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  WHERE p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),
user_badges AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
user_top_tags AS (
  SELECT UserId, TopTag
  FROM (
    SELECT p.OwnerUserId AS UserId,
           ta.TagName AS TopTag,
           COUNT(*) AS TagCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(regexp_replace(p.Tags, '^<|>$', '', 'g'), '><')) AS ta(TagName)
    WHERE p.OwnerUserId > 0 AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, ta.TagName
  ) s
  WHERE rn = 1
),
activity_set AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(up.LastActivityDate, u.CreationDate) AS LastActivityDate,
    (2.0 * COALESCE(up.PostCount, 0)
     + 1.5 * COALESCE(up.PostScore, 0)
     + 1.5 * COALESCE(rv.UpvotesReceived, 0)
     - 1.0 * COALESCE(rv.DownvotesReceived, 0)
     + 0.3 * COALESCE(vc.UpvotesCast, 0)
     - 0.2 * COALESCE(vc.DownvotesCast, 0)
     + 5.0 * COALESCE(bg.GoldBadges, 0)
     + 3.0 * COALESCE(bg.SilverBadges, 0)
     + 1.0 * COALESCE(bg.BronzeBadges, 0)
    ) AS Score,
    'ActivityScore' AS ScoreType
  FROM Users u
  LEFT JOIN user_posts up ON up.UserId = u.Id
  LEFT JOIN user_votes_received rv ON rv.UserId = u.Id
  LEFT JOIN user_votes_cast vc ON vc.UserId = u.Id
  LEFT JOIN user_badges bg ON bg.UserId = u.Id
  LEFT JOIN user_top_tags tt ON tt.UserId = u.Id
  ORDER BY Score DESC
  LIMIT 100
),
recent_set AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     COALESCE(up.LastActivityDate, u.CreationDate) AS LastActivityDate,
     0.0 AS Score,
     'RecentActivity' AS ScoreType
  FROM Users u
  LEFT JOIN (
     SELECT OwnerUserId, MAX(LastActivityDate) AS LastActivityDate
     FROM Posts
     WHERE OwnerUserId > 0
     GROUP BY OwnerUserId
  ) up ON up.OwnerUserId = u.Id
  ORDER BY LastActivityDate DESC
  LIMIT 100
)
SELECT *
FROM activity_set
UNION ALL
SELECT *
FROM recent_set
ORDER BY Score DESC
LIMIT 200;