-- {"query": "5946.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 592}
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountRecent
  FROM Comments c
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  GROUP BY c.PostId
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location
  FROM Users u
  WHERE u.Reputation > 1000
)
SELECT
  rq.PostId,
  rq.Title AS QuestionTitle,
  rq.CreationDate AS QuestionCreated,
  rq.OwnerUserId,
  rq.Score AS QuestionScore,
  rq.ViewCount,
  rq.Tags,
  rq.LastActivityDate,
  rq.AnswerCount,
  COALESCE(rc.CommentCountRecent, 0) AS RecentCommentCount,
  tu.UserId AS TopResponderUserId,
  tu.DisplayName AS TopResponder,
  tu.Reputation AS TopResponderRep,
  (rq.ViewCount * 0.5 + rq.AnswerCount * 4 + COALESCE(rc.CommentCountRecent, 0) * 2) AS EngagementScore,
  DENSE_RANK() OVER (ORDER BY tu.Reputation DESC) AS ResponderRank
FROM recent_questions rq
LEFT JOIN recent_comments rc ON rc.PostId = rq.PostId
LEFT JOIN LATERAL (
  SELECT
    p.Id AS QuestionId,
    a.OwnerUserId AS UserId,
    u.DisplayName
  FROM Posts a
  JOIN Posts p ON p.Id = a.ParentId
  JOIN Users u ON u.Id = a.OwnerUserId
  WHERE a.PostTypeId = 2
    AND p.Id = rq.PostId
  ORDER BY a.Score DESC
  LIMIT 1
) top_ans ON top_ans.QuestionId = rq.PostId
LEFT JOIN top_users tu ON tu.UserId = top_ans.UserId
WHERE rq.Title IS NOT NULL
ORDER BY EngagementScore DESC, rq.LastActivityDate DESC
LIMIT 200;