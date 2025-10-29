-- {"query": "5575.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 750}
WITH ranked_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (
      ORDER BY u.Reputation DESC,
               (u.UpVotes - u.DownVotes) DESC,
               u.LastAccessDate DESC
    ) AS rn
  FROM Users u
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.TagName IS NOT NULL
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
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY)
),
complex_post_history AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16, 24)
),
linked_posts AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
),
combined AS (
  SELECT
    up.Id AS UserId,
    up.DisplayName AS UserName,
    up.rn AS UserRank,
    tt.rn AS TagRank,
    rq.PostId AS QuestionId,
    rq.Title AS QuestionTitle,
    rq.CreationDate AS QuestionDate,
    rq.Score AS QuestionScore,
    rq.ViewCount AS QuestionViews,
    rq.Tags AS QuestionTags,
    rq.AnswerCount,
    rq.CommentCount,
    ch.HistoryId,
    ch.PostHistoryTypeId,
    ch.CreationDate AS HistoryDate,
    ch.UserId AS HistoryUserId,
    ch.Comment AS HistoryComment,
    lp.Id AS LinkId,
    lp.RelatedPostId,
    lp.LinkTypeId,
    lp.CreationDate AS LinkDate
  FROM ranked_users up
  LEFT JOIN Posts q ON q.OwnerUserId = up.Id AND q.PostTypeId = 1
  LEFT JOIN recent_questions rq ON rq.PostId = q.Id
  LEFT JOIN complex_post_history ch ON ch.PostId = q.Id
  LEFT JOIN linked_posts lp ON lp.PostId = q.Id
  LEFT JOIN top_tags tt ON tt.TagName = SUBSTRING(q.Tags FROM 2 FOR CHAR_LENGTH(q.Tags) - 2)
  WHERE up.rn <= 100
)
SELECT
  UserId,
  UserName,
  UserRank,
  TagRank,
  QuestionId,
  QuestionTitle,
  QuestionDate,
  QuestionScore,
  QuestionViews,
  QuestionTags,
  AnswerCount,
  CommentCount,
  HistoryId,
  PostHistoryTypeId,
  HistoryDate,
  HistoryUserId,
  HistoryComment,
  LinkId,
  RelatedPostId,
  LinkTypeId,
  LinkDate
FROM combined
ORDER BY UserRank, QuestionDate DESC
LIMIT 100;