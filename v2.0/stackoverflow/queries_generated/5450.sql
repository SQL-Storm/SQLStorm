-- {"query": "5450.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 885} 
WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC, u.Reputation DESC NULLS LAST) AS rn
  FROM Users u
  WHERE u.LastAccessDate IS NOT NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC, t.Id DESC) AS tag_rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
ActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p closed AS ClosedFlag
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND (p.ClosedDate IS NULL)
),
CommentedPosts AS (
  SELECT
    a.PostId,
    COUNT(*) AS CommentCount
  FROM Comments a
  GROUP BY a.PostId
),
JoinedActivity AS (
  SELECT
    ap.PostId,
    ap.PostTypeId,
    ap.Title,
    ap.OwnerUserId,
    ep.DisplayName AS OwnerDisplayName,
    ap.CreationDate,
    ap.LastActivityDate,
    ap.Score,
    ap.ViewCount,
    ap.Tags,
    ic.CommentCount,
    COALESCE(ct.CommentCount, 0) AS TotalComments,
    CASE
      WHEN ap.OwnerUserId IS NULL THEN 'Unknown'
      ELSE 'Known'
    END AS OwnerKnown
  FROM ActivePosts ap
  LEFT JOIN Users ep ON ep.Id = ap.OwnerUserId
  LEFT JOIN CommentedPosts ic ON ic.PostId = ap.PostId
  LEFT JOIN Comments ct ON ct.PostId = ap.PostId
  GROUP BY ap.PostId, ap.PostTypeId, ap.Title, ap.OwnerUserId, ep.DisplayName, ap.CreationDate, ap.LastActivityDate, ap.Score, ap.ViewCount, ap.Tags, ic.CommentCount
)
SELECT
  ju.PostId,
  ju.PostTypeId,
  ju.Title,
  ju.OwnerUserId,
  ju.OwnerDisplayName,
  ju.CreationDate,
  ju.LastActivityDate,
  ju.Score,
  ju.ViewCount,
  ju.Tags,
  ju.TotalComments,
  ju.OwnerKnown,
  -- Complex string expression across multiple fields
  CONCAT_WS(' | ', COALESCE(TO_CHAR(ju.CreationDate, 'YYYY-MM-DD HH24:MI'), ''), COALESCE(TO_CHAR(ju.LastActivityDate, 'YYYY-MM-DD HH24:MI'), ''), ju.Tags) AS ActivitySignature,
  -- Window function to assign ranking by score within a 7-day window
  DENSE_RANK() OVER (
    PARTITION BY CAST(ju.LastActivityDate AS DATE)
    ORDER BY ju.Score DESC NULLS LAST, ju.ViewCount DESC NULLS LAST
  ) AS DailyScoreRank,
  -- Boolean-like predicate with NULL-safe logic
  CASE
    WHEN ju.OwnerUserId IS NULL THEN FALSE
    WHEN ju.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 1000) THEN TRUE
    ELSE NULL
  END AS IsPromisingOwner
FROM JoinedActivity ju
ORDER BY ju.LastActivityDate DESC
LIMIT 100;