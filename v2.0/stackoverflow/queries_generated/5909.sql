-- {"query": "5909.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 782} 
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TopQuestions AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.ViewCount,
    ra.Score,
    ra.OwnerUserId,
    ra.Tags,
    ra.PostTypeId
  FROM RecentActive ra
  WHERE ra.PostTypeId = 1 AND ra.rn = 1
),
LastActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.LastActivityDate AS ActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.PostTypeId
  FROM Posts p
),
Enriched AS (
  SELECT
    tq.PostId,
    tq.Title AS QuestionTitle,
    tq.CreationDate AS QuestionCreated,
    ta.ActivityDate AS LastActivityDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.Location,
    ta.Tags,
    ta.ViewCount,
    ta.Score,
    ta.PostTypeId,
    -- compute a complex derived metric: activity_score combines activity recency and score
    (DATEDIFF(day, tq.CreationDate, GETDATE()) * 2 + ta.Score) AS ActivityScore,
    -- string expression: count of tags by splitting Tags field if present
    CARDINALITY(string_to_array(substr(ta.Tags, 2, length(ta.Tags)-2), '><')) AS TagCount
  FROM TopQuestions tq
  LEFT JOIN Posts ta ON ta.Id = tq.PostId
  LEFT JOIN Users u ON u.Id = tq.OwnerUserId
),
CrossRefs AS (
  SELECT
    e.PostId,
    e.QuestionTitle,
    e.QuestionCreated,
    e.LastActivityDate,
    e.OwnerName,
    e.Reputation,
    e.Location,
    e.Tags,
    e.ViewCount,
    e.Score,
    e.PostTypeId,
    e.ActivityScore,
    e.TagCount,
    -- join with related posts via PostLinks to explore graph-like connectivity
    pl.RelatedPostId,
    p2.Title AS RelatedTitle,
    p2.CreationDate AS RelatedCreated
  FROM Enriched e
  LEFT JOIN PostLinks pl ON pl.PostId = e.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
),
Final AS (
  SELECT
    cr.PostId,
    cr.QuestionTitle,
    cr.QuestionCreated,
    cr.LastActivityDate,
    cr.OwnerName,
    cr.Reputation,
    cr.Location,
    cr.Tags,
    cr.ViewCount,
    cr.Score,
    cr.PostTypeId,
    cr.ActivityScore,
    cr.TagCount,
    cr.RelatedPostId,
    cr.RelatedTitle,
    cr.RelatedCreated
  FROM CrossRefs cr
  ORDER BY cr.ActivityScore DESC NULLS LAST
)
SELECT
  f.PostId,
  f.QuestionTitle,
  f.QuestionCreated,
  f.LastActivityDate,
  f.OwnerName,
  f.Reputation,
  f.Location,
  f.Tags,
  f.ViewCount,
  f.Score,
  f.PostTypeId,
  f.ActivityScore,
  f.TagCount,
  f.RelatedPostId,
  f.RelatedTitle,
  f.RelatedCreated
FROM Final f
LIMIT 100;