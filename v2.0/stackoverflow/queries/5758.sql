-- {"query": "5758.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 948}
WITH top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY u.Location
      ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC
    ) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
tag_wise_activity AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_questions,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS positive_scores,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS highly_viewed
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(p.Tags, '>')) AS tag
  ) s ON true
  JOIN Tags t ON t.TagName = NULLIF(REGEXP_REPLACE(s.tag, '^[\\,<>]*|[<>]', '', 'g'), '')
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    COALESCE(LEAD(p.LastActivityDate) OVER (ORDER BY p.LastActivityDate DESC), p.LastActivityDate) AS NextActivity
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
complex_joins AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    pc.Id AS ClosestCommentUser,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    p.ViewCount,
    p.Score AS PostScore,
    p.Tags,
    b.Name AS BadgeName
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Users pc ON pc.Id = c.UserId
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.RelatedPostId = p.Id
)
SELECT
  tu.Id AS UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.Location,
  tu.CreationDate,
  tu.LastAccessDate,
  tu.Views,
  tu.UpVotes,
  tu.DownVotes,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.Id AND p.PostTypeId = 1) AS QuestionsOwned,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.Id AND p.PostTypeId = 2) AS AnswersOwned,
  (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = tu.Id) AS AvgPostScore,
  (SELECT MAX(s) - MIN(s)
     FROM (SELECT p2.Score AS s FROM Posts p2 WHERE p2.OwnerUserId = tu.Id) sub) AS ScoreRange,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.Id AND p.Tags IS NOT NULL) AS TaggedPosts,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.Id AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14 days') AS RecentlyActivePosts,
  EXISTS (
    SELECT 1
    FROM Votes v
    JOIN PostHistory ph ON ph.PostId = v.PostId
    WHERE v.UserId = tu.Id
      AND ph.PostHistoryTypeId = 10
      AND ph.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
  ) AS HasRecentCloseVotes
FROM top_users tu
WHERE tu.rn = 1
ORDER BY tu.Reputation DESC, tu.LastAccessDate DESC
LIMIT 100;