-- {"query": "5490.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 872} 
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
    u.Location,
    u.WebsiteUrl,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY (CASE WHEN u.Reputation < 1000 THEN 0 ELSE 1 END)
      ORDER BY u.Reputation DESC, u.Views DESC, u.LastAccessDate DESC
    ) AS rn
  FROM Users u
),
recent_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ',') AS BadgesList
  FROM Badges b
  WHERE b.Date >= NOW() - INTERVAL '1 year'
  GROUP BY b.UserId
),
top_posts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    p.Tags,
    ROW_NUMBER() OVER (
      ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.LastActivityDate DESC
    ) AS pos
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
    AND p.ClosedDate IS NULL
),
complex_metrics AS (
  SELECT
    tp.OwnerUserId,
    SUM(tp.Score) AS total_score_all_posts,
    SUM(CASE WHEN tp.PostTypeId = 1 THEN 1 ELSE 0 END) AS total_questions,
    SUM(CASE WHEN tp.PostTypeId = 2 THEN 1 ELSE 0 END) AS total_answers,
    AVG(tp.Score) FILTER (WHERE tp.PostTypeId = 1) AS avg_question_score,
    MAX(tp.Score) AS max_post_score,
    MIN(tp.Score) AS min_post_score,
    STRING_AGG(DISTINCT tp.Tags, '|') AS all_tags
  FROM top_posts tp
  GROUP BY tp.OwnerUserId
),
correlated_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    MAX(c.CreationDate) AS last_comment
  FROM Comments c
  GROUP BY c.PostId
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT p.Id) AS posts_count,
    COUNT(DISTINCT c.Id) AS comments_count,
    MAX(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY u.Id
)
SELECT
  ru.Id AS UserId,
  ru.DisplayName AS UserName,
  ru.Reputation,
  ru.CreationDate,
  ru.LastAccessDate,
  ru.Location,
  ru.WebsiteUrl,
  rb.BadgeCount,
  rb.BadgesList,
  cm.total_score_all_posts,
  cm.total_questions,
  cm.total_answers,
  cm.avg_question_score,
  ca.posts_count,
  ca.comments_count,
  ca.last_activity,
  tp0.Title AS sample_post_title,
  tp0.Score AS sample_post_score,
  tp0.ViewCount AS sample_post_views,
  tp0.PostTypeId AS sample_post_type
FROM ranked_users ru
LEFT JOIN recent_badges rb ON rb.UserId = ru.Id
LEFT JOIN complex_metrics cm ON cm.OwnerUserId = ru.Id
LEFT JOIN author_activity ca ON ca.UserId = ru.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    p.Title
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  ORDER BY p.CreationDate DESC
  LIMIT 1
) tp0 ON tp0.OwnerUserId = ru.Id
WHERE ru.rn = 1
  AND (rb.BadgeCount IS NULL OR rb.BadgeCount > 0)
ORDER BY ru.Reputation DESC NULLS LAST, ru.LastAccessDate DESC
LIMIT 100;