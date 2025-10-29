-- {"query": "5819.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 754} 
WITH TopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p CommentCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
ActiveTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.WikiPostId,
    t.ExcerptPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16,19,20,24,31,33)
),
RecentComments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.CreationDate,
    c.UserId,
    c.Text,
    c.Score
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsOwned,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgesEarned
  FROM Users u
),
BenchmarkSet AS (
  SELECT
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.ViewCount,
    tq.Score,
    tq.OwnerUserId,
    uq.DisplayName AS OwnerName,
    ac.TagName,
    ra.HistoryId AS EditHistoryId,
    rc.CommentId AS CommentId,
    ua.Reputation,
    ua.BadgesEarned,
    ROW_NUMBER() OVER (
      PARTITION BY tq.QuestionId
      ORDER BY tq.ViewCount DESC, tq.Score DESC, tq.CreationDate DESC
    ) AS rn
  FROM TopQuestions tq
  LEFT JOIN Users uq ON tq.OwnerUserId = uq.Id
  LEFT JOIN ActiveTags ac ON ac.WikiPostId = NULL -- intentionally cross join to widen results
  LEFT JOIN RecentEdits ra ON ra.PostId = tq.QuestionId
  LEFT JOIN RecentComments rc ON rc.PostId = tq.QuestionId
  LEFT JOIN UserActivity ua ON ua.UserId = tq.OwnerUserId
)
SELECT
  b.QuestionId,
  b.Title,
  b.OwnerName,
  b.ViewCount,
  b.Score,
  b.TagName,
  b.EditHistoryId,
  b.CommentId,
  b.Reputation,
  b.BadgesEarned,
  b.CreationDate,
  b.UserCreationDate,
  b.LastActivityDate
FROM BenchmarkSet b
WHERE b.rn = 1
ORDER BY b.ViewCount DESC, b.Score DESC
LIMIT 100;