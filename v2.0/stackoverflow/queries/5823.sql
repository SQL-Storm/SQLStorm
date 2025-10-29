-- {"query": "5823.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1093}
WITH
Dates AS (
  SELECT date_trunc('day', CreationDate) AS d
  FROM Posts
  GROUP BY date_trunc('day', CreationDate)
),
DailyActivity AS (
  SELECT
    d.d AS day_date,
    p.Id AS post_id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_by_user,
    SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS cum_score_by_user,
    AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
    COUNT(*) OVER (PARTITION BY p.PostTypeId) AS posts_of_type
  FROM Posts p
  JOIN Dates d ON date_trunc('day', p.CreationDate) = d.d
),
PostComments AS (
  SELECT
    a.post_id,
    a.PostTypeId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.post_id AND c.UserId IS NOT NULL) AS comment_count_nonnull_user
  FROM DailyActivity a
),
EditorInfo AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.LastActivityDate,
    (SELECT v.CreationDate
     FROM Votes v
     WHERE v.PostId = p.Id
     ORDER BY v.CreationDate DESC
     LIMIT 1) AS last_vote_date
  FROM Posts p
),
UserMeta AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS badge_count
  FROM Users u
),
ComplexFlags AS (
  SELECT
    a.day_date,
    a.post_id,
    a.PostTypeId,
    a.Score,
    a.ViewCount,
    CASE
      WHEN a.Score > 0 AND a.ViewCount > 100 THEN TRUE
      WHEN a.Score <= 0 AND a.ViewCount > 1000 THEN TRUE
      ELSE FALSE
    END AS high_engagement,
    CASE
      WHEN a.Title IS NULL THEN 'untitled'
      WHEN LENGTH(a.Title) < 5 THEN 'short'
      ELSE 'normal'
    END AS title_length_category,
    TRIM(a.Title) AS trimmed_title
  FROM DailyActivity a
),
Links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.LinkTypeId IN (1,3)
),
Unioned AS (
  SELECT day_date, post_id, PostTypeId, Score, ViewCount, high_engagement, title_length_category, trimmed_title
  FROM ComplexFlags
  UNION ALL
  SELECT d AS day_date,
         CAST(NULL AS BIGINT) AS post_id,
         CAST(NULL AS INTEGER) AS PostTypeId,
         CAST(NULL AS INTEGER) AS Score,
         CAST(NULL AS INTEGER) AS ViewCount,
         CAST(NULL AS BOOLEAN) AS high_engagement,
         CAST(NULL AS VARCHAR) AS title_length_category,
         CAST(NULL AS VARCHAR) AS trimmed_title
  FROM Dates
)
SELECT
  um.UserId,
  um.DisplayName,
  um.Reputation,
  um.badge_count,
  cf.day_date,
  cf.post_id,
  cf.PostTypeId,
  cf.Score,
  cf.ViewCount,
  a.cum_score_by_user,
  a.avg_score_by_type,
  a.posts_of_type,
  b.comment_count_nonnull_user,
  e.LastEditorUserId,
  e.LastEditorDisplayName,
  e.LastEditDate,
  e.last_vote_date,
  cf.high_engagement,
  cf.title_length_category,
  cf.trimmed_title,
  l.RelatedPostId,
  l.LinkTypeName
FROM Unioned cf
LEFT JOIN DailyActivity a ON a.day_date = cf.day_date AND a.post_id = cf.post_id
LEFT JOIN PostComments b ON b.post_id = cf.post_id
LEFT JOIN EditorInfo e ON e.PostId = cf.post_id
LEFT JOIN Links l ON l.PostId = cf.post_id
LEFT JOIN UserMeta um ON um.UserId = a.OwnerUserId
ORDER BY um.DisplayName, cf.day_date, cf.post_id
LIMIT 100;