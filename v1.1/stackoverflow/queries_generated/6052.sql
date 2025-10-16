-- {"query": "6052.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1022} 
WITH
_recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= now() - interval '180 days'
),
_recent_answers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreationDate,
    a.OwnerUserId AS AnswerOwnerId
  FROM Posts a
  WHERE a.PostTypeId = 2 -- Answers
    AND a.CreationDate >= now() - interval '180 days'
),
_user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.AccountId,
    CASE
      WHEN u.Reputation >= 10000 THEN 'Diamond'
      WHEN u.Reputation >= 5000 THEN 'Sapphire'
      WHEN u.Reputation >= 1000 THEN 'Emerald'
      ELSE 'Bronze'
    END AS Tier
  FROM Users u
),
_tag_summary AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    MAX(p.CreationDate) AS LastTagQuestionDate
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%' AND p.PostTypeId = 1
  GROUP BY t.TagName
),
_expanded_tags AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
),
_related_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate AS LinkCreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name ILIKE '%Linked%' OR lt.Name ILIKE '%Duplicate%'
),
_complex_calculations AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    (q.Score * 1.0) / NULLIF(q.ViewCount, 0) AS ScorePerView,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCountOnQuestion,
    (SELECT STRING_AGG(DISTINCT vt.Name, ',') 
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = q.PostId) AS VoteTypesOnQuestion
  FROM _recent_questions q
  LEFT JOIN _recent_answers a ON a.QuestionId = q.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.Tier AS OwnerTier,
  a.AnswerCount AS AnswerCount,
  c.ScorePerView,
  c.CommentCountOnQuestion,
  c.VoteTypesOnQuestion,
  COALESCE(rl.LinkCreationDate, NULL) AS RelatedLinkDate,
  rl.RelatedPostId,
  lt.Name AS LinkTypeName,
  ts.TagName,
  ts.TagQuestionCount,
  ts.AvgQuestionScore,
  ts.LastTagQuestionDate
FROM _complex_calculations c
JOIN _user_stats u ON c.OwnerUserId = u.UserId
LEFT JOIN _recent_answers a ON a.QuestionId = c.PostId
LEFT JOIN _related_links rl ON rl.PostId = c.PostId
LEFT JOIN LinkTypes lt ON rl.LinkTypeName = lt.Name
LEFT JOIN _expanded_tags et ON et.PostId = c.PostId
LEFT JOIN _tag_summary ts ON ts.TagName = et.TagName
WHERE
  (c.ScorePerView > 0.5 OR c.AnswerCount >= 5)
  AND (c.CommentCountOnQuestion IS NULL OR c.CommentCountOnQuestion >= 2)
ORDER BY
  c.CreationDate DESC
LIMIT 200;