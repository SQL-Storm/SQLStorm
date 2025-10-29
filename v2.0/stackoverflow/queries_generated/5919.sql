-- {"query": "5919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1012} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
QuestionTagStats AS (
  SELECT
    q.PostId,
    t.TagName,
    COUNT(*) OVER (PARTITION BY q.PostId) AS TagCountInQuestion,
    SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY q.PostId) AS HasGoldBadge
  FROM RecentTopQuestions q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
  ) t
  LEFT JOIN Badges b ON b.TagBased = 1 AND b.Name ILIKE '%' || t.TagName || '%'
  AND b.UserId IN (SELECT Id FROM Users WHERE Reputation > 1000)
),
ComplexPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    STRING_AGG(CONCAT_WS(':', v.VoteTypeId, v.UserId, v.CreationDate), '|') AS VotesInfo
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount
),
Correlation AS (
  SELECT
    c1.PostId,
    c1.Title,
    c1.OwnerUserId,
    c1.CreationDate,
    c1.LastActivityDate,
    c1.Score,
    c1.ViewCount,
    c1.CommentCount,
    c1.FavoriteCount,
    c1.VotesInfo,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = c1.OwnerUserId) AS AvgOwnerScore,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = c1.OwnerUserId) AS OwnerPostCount
  FROM ComplexPosts c1
),
OuterJoinExample AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.FavoriteCount,
    ao.AvgOwnerScore,
    ao.OwnerPostCount,
    ct.TagName,
    ct.TagCountInQuestion,
    ct.HasGoldBadge
  FROM RecentTopQuestions r
  LEFT JOIN Correlation ao ON ao.PostId = r.PostId
  LEFT JOIN QuestionTagStats ct ON ct.PostId = r.PostId
  WHERE r.rn <= 200
),
Windowed AS (
  SELECT
    o.*,
    SUM(o.ViewCount) OVER (PARTITION BY o.OwnerUserId ORDER BY o.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS RollingViews24q
  FROM OuterJoinExample o
),
Final AS (
  SELECT DISTINCT
    w.PostId,
    w.Title,
    w.OwnerUserId,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.CommentCount,
    w.FavoriteCount,
    w.AvgOwnerScore,
    w.OwnerPostCount,
    w.TagName,
    w.TagCountInQuestion,
    w.HasGoldBadge,
    w.RollingViews24q
  FROM Windowed w
  ORDER BY w.Score DESC, w.ViewCount DESC
  LIMIT 100
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerUserId,
  (SELECT DisplayName FROM Users u WHERE u.Id = f.OwnerUserId) AS OwnerDisplayName,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.CommentCount,
  f.FavoriteCount,
  f.AvgOwnerScore,
  f.OwnerPostCount,
  f.TagName,
  f.TagCountInQuestion,
  f.HasGoldBadge,
  f.RollingViews24q
FROM Final f;