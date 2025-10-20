-- {"query": "356.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25979} 
WITH
  user_base AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate
    FROM Users u
  ),
  post_counts AS (
    SELECT OwnerUserId AS UserId,
           COUNT(*) AS TotalPosts,
           SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
           SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
           AVG(Score) AS AvgScore,
           MAX(CreationDate) AS LastPostDate
    FROM Posts
    GROUP BY OwnerUserId
  ),
  user_stats AS (
    SELECT bu.UserId,
           bu.DisplayName,
           bu.Reputation,
           bu.CreationDate,
           bu.LastAccessDate,
           COALESCE(pc.TotalPosts, 0) AS TotalPosts,
           COALESCE(pc.QuestionCount, 0) AS QuestionCount,
           COALESCE(pc.AnswerCount, 0) AS AnswerCount,
           COALESCE(pc.AvgScore, 0) AS AvgScore,
           COALESCE(pc.LastPostDate, TIMESTAMP 'epoch') AS LastPostDate
    FROM user_base bu
    LEFT JOIN post_counts pc ON pc.UserId = bu.UserId
  ),
  last_activity AS (
    SELECT us.UserId,
           us.DisplayName,
           GREATEST(us.LastPostDate, COALESCE(v.LastVoteDate, TIMESTAMP 'epoch')) AS LastActivity
    FROM user_stats us
    LEFT JOIN (
       SELECT UserId, MAX(CreationDate) AS LastVoteDate
       FROM Votes
       GROUP BY UserId
    ) v ON v.UserId = us.UserId
  ),
  tag_names AS (
    SELECT p.OwnerUserId AS UserId,
           STRING_AGG(DISTINCT tn.TagName, ',') AS DistinctTags
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) AS tn(TagName)
    WHERE p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
  ),
  top_type AS (
    SELECT UserId, TopTypeId
    FROM (
      SELECT OwnerUserId AS UserId, PostTypeId AS TopTypeId, COUNT(*) AS TypeCount,
             ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC) AS rn
      FROM Posts
      GROUP BY OwnerUserId, PostTypeId
    ) AS t
    WHERE rn = 1
  ),
  last_post_id AS (
    SELECT u.Id AS UserId,
           (SELECT Id FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.CreationDate DESC LIMIT 1) AS LastPostId
    FROM Users u
  )
SELECT
  'FULL' AS Source,
  la.UserId,
  la.DisplayName,
  la.LastActivity AS LastActivity,
  us.Reputation,
  us.TotalPosts,
  tn.DistinctTags,
  tt.TopTypeId,
  lpi.LastPostId
FROM last_activity la
LEFT JOIN user_stats us ON us.UserId = la.UserId
LEFT JOIN tag_names tn ON tn.UserId = la.UserId
LEFT JOIN top_type tt ON tt.UserId = la.UserId
LEFT JOIN last_post_id lpi ON lpi.UserId = la.UserId
UNION ALL
SELECT
  'MIN' AS Source,
  la.UserId,
  la.DisplayName,
  la.LastActivity AS LastActivity,
  NULL AS Reputation,
  NULL AS TotalPosts,
  NULL AS DistinctTags,
  NULL AS TopTypeId,
  NULL AS LastPostId
FROM last_activity la
ORDER BY LastActivity DESC NULLS LAST
LIMIT 200;