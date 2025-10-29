-- {"query": "5423.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 782} 
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
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_activities AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    COALESCE(v.BountyAmount, 0) AS BountyAmount,
    COALESCE(cl.Name, 'Unknown') AS CloseReason
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN CloseReasonTypes cl ON CAST(NULL AS smallint) IS NOT NULL -- placeholder to keep structure
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.LastActivityDate > NOW() - INTERVAL '180 days'
),
correlated_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_pred AS (
  SELECT
    u.UserId,
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
    ta.PostId,
    ta.Title,
    ta.PostTypeId,
    ta.CreationDate AS PostCreationDate,
    ta.LastActivityDate AS PostLastActivityDate,
    ta.Score,
    ta.ViewCount,
    ta.Tags,
    ta.AnswerCount,
    ta.BountyAmount
  FROM top_users u
  LEFT JOIN recent_activities ta ON ta.OwnerUserId = u.UserId
  LEFT JOIN correlated_tags ct ON ta.Tags LIKE '%' || ct.TagName || '%'
  WHERE u.Reputation > 1000
    OR EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = u.UserId
        AND p.Score > 50
    )
),
windowed AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY PostLastActivityDate DESC) AS rn_post
  FROM complex_pred c
)
SELECT
  u.DisplayName,
  u.Reputation,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  p.AnswerCount,
  p.BountyAmount
FROM windowed w
JOIN Users u ON w.UserId = u.Id
LEFT JOIN Posts p ON w.PostId = p.Id
WHERE
  w.rn_post = 1
  AND (p.Title IS NULL OR LEN(p.Title) > 5)
ORDER BY u.Reputation DESC, p.Score DESC, p.LastActivityDate DESC
LIMIT 100;