-- {"query": "5749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 976} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
open_closed AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.ClosedDate,
    pb.Name AS CloseReason,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN CloseReasonTypes pb ON CAST(ph.Comment AS varchar) LIKE '%' || pb.Id || '%'
  WHERE p.ClosedDate IS NOT NULL
),
tag_popularity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.Count > 50
),
activity_by_tag AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    COUNT(*) AS mentions
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY tag
),
complex_query AS (
  SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    q.PostId,
    q.Title AS QuestionTitle,
    q.Tags,
    q.CreationDate AS QuestionDate,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViews,
    a.PostId AS AnswerPostId,
    a.LastActivityDate AS AnswerDate,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.BountyAmount,
    pr.CloseReasonId,
    pr.CloseReason,
    ARRAY_AGG(DISTINCT tg.tag) FILTER (WHERE tg.tag IS NOT NULL) AS tags_seen
  FROM top_users u
  LEFT JOIN recent_questions q ON q.OwnerUserId = u.UserId
  LEFT JOIN Posts a ON a.ParentId = q.PostId OR a.Id = q.PostId
  LEFT JOIN Votes v ON v.PostId = q.PostId
  LEFT JOIN (
    SELECT ph.PostId, ph.Comment AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
  ) pr ON pr.PostId = q.PostId
  LEFT JOIN (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag, p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) tg ON tg.PostId = q.PostId
  WHERE u.Reputation IS NOT NULL
  GROUP BY
    u.UserId, u.DisplayName, u.Reputation, u.Location,
    q.PostId, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount,
    a.PostId, a.LastActivityDate, v.VoteTypeId, v.CreationDate, v.BountyAmount,
    pr.CloseReasonId, pr.CloseReason
)
SELECT
  cu.rn AS ranked_user,
  cu.UserId,
  cu.DisplayName,
  cu.Reputation,
  cu.Location,
  cu.PostId AS RecentQuestionId,
  cu.QuestionTitle,
  cu.Tags AS QuestionTags,
  cu.QuestionDate,
  cu.QuestionScore,
  cu.QuestionViews,
  cu.AnswerPostId,
  cu.AnswerDate,
  cu.VoteTypeId,
  cu.VoteDate,
  cu.BountyAmount,
  cu.CloseReason,
  cu.tags_seen
FROM complex_query cu
WHERE cu.Reputation > 500
  AND cu.QuestionDate >= NOW() - INTERVAL '180 days'
ORDER BY cu.Reputation DESC, cu.QuestionDate DESC
LIMIT 100;