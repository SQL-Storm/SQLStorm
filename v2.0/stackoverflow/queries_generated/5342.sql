-- {"query": "5342.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1040} 
WITH
active_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate > NOW() - INTERVAL '365 days'
),
question_history AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 16)
),
complex_post_links AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3) -- Linked or Duplicate
),
post_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId, v.VoteTypeId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  WHERE v.VoteTypeId IN (2, 3, 10, 12, 14, 15, 16)
),
rare_combination AS (
  SELECT
    q.PostId,
    q.Title AS QuestionTitle,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    t.TagName,
    u.DisplayName AS OwnerDisplayName,
    h.Comment AS HistoryComment,
    v.VoteTypeId AS LastVoteTypeId,
    v.CreationDate AS LastVoteDate
  FROM recent_questions q
  LEFT JOIN Posts p2 ON p2.ParentId = q.PostId
  LEFT JOIN unnest(string_to_array(q.Tags, '>')) AS tname(tag) ON TRUE
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN question_history h ON h.PostId = q.PostId
  LEFT JOIN post_votes v ON v.PostId = q.PostId AND v.rn = 1
  WHERE q.OwnerUserId IS NOT NULL
)
SELECT
  ur.UserId,
  ur.DisplayName AS UserDisplayName,
  ur.Reputation,
  ur.CreationDate AS UserCreationDate,
  ur.LastAccessDate,
  ur.Location,
  ur.Views,
  ur.UpVotes,
  ur.DownVotes,
  ur.AccountId,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ur.UserId AND p.PostTypeId = 1) AS UserQuestionCount,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ur.UserId AND p.PostTypeId = 2) AS UserAnswerCount,
  (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ur.UserId) AS AvgPostScore,
  (SELECT STRING_AGG(DISTINCT t.TagName, ',') FROM Tags t
     JOIN Posts p ON p.Id = t.ExcerptPostId
     WHERE p.OwnerUserId = ur.UserId) AS TopTagsLiked,
  rq.PostId AS RecentQuestionId,
  rq.QuestionTitle,
  rq.CreationDate AS QuestionCreationDate,
  rq.Score AS QuestionScore,
  rq.ViewCount AS QuestionViews,
  rq.TagName AS PrimaryTag,
  rq.OwnerDisplayName AS QuestionOwner,
  rq.LastActivityDate AS QuestionLastActivity
FROM active_users ur
LEFT JOIN rare_combination rq ON rq.OwnerDisplayName = ur.DisplayName
LEFT JOIN top_tags tt ON tt.rn = 1
LEFT JOIN complex_post_links cpl ON cpl.PostId = rq.PostId
LEFT JOIN post_votes pv ON pv.PostId = rq.PostId AND pv.rn = 1
ORDER BY ur.Reputation DESC, rq.QuestionCreationDate DESC
LIMIT 100;