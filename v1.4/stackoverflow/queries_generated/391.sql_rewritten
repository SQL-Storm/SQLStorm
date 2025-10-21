-- {"query": "391.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18437} 
WITH
recent_questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, p.Tags, p.ClosedDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
),
tag_expansion AS (
  SELECT rq.Id AS QuestionId, t.TagName
  FROM recent_questions rq
  CROSS JOIN LATERAL unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS t(TagName)
),
tag_counts AS (
  SELECT QuestionId, TagName, COUNT(*) AS TagCount
  FROM tag_expansion
  GROUP BY QuestionId, TagName
),
top3_tags AS (
  SELECT s.QuestionId,
         STRING_AGG(s.TagName, ', ' ORDER BY s.TagCount DESC) AS Top3Tags
  FROM (
    SELECT QuestionId, TagName, TagCount,
           ROW_NUMBER() OVER (PARTITION BY QuestionId ORDER BY TagCount DESC, TagName ASC) AS rn
    FROM tag_counts
  ) s
  WHERE s.rn <= 3
  GROUP BY s.QuestionId
),
open_set AS (
  SELECT rq.Id AS QuestionId,
         rq.Title,
         rq.CreationDate,
         rq.ViewCount,
         rq.Score,
         u.DisplayName AS OwnerDisplayName,
         rq.ClosedDate,
         (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = rq.Id AND p2.PostTypeId = 2) AS AnswerCount,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id) AS CommentCount,
         COALESCE(tt.Top3Tags, '') AS Top3Tags,
         COALESCE((SELECT v.BountyAmount FROM Votes v WHERE v.PostId = rq.Id AND v.VoteTypeId = 8 ORDER BY v.CreationDate DESC LIMIT 1), 0) AS LastBountyAmount,
         CASE WHEN rq.ViewCount = 0 THEN NULL ELSE rq.Score * 1.0 / rq.ViewCount END AS ScorePerView
  FROM recent_questions rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN top3_tags tt ON tt.QuestionId = rq.Id
  WHERE rq.ClosedDate IS NULL
),
closed_set AS (
  SELECT rq.Id AS QuestionId,
         rq.Title,
         rq.CreationDate,
         rq.ViewCount,
         rq.Score,
         u.DisplayName AS OwnerDisplayName,
         rq.ClosedDate,
         (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = rq.Id AND p2.PostTypeId = 2) AS AnswerCount,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id) AS CommentCount,
         COALESCE(tt.Top3Tags, '') AS Top3Tags,
         COALESCE((SELECT v.BountyAmount FROM Votes v WHERE v.PostId = rq.Id AND v.VoteTypeId = 8 ORDER BY v.CreationDate DESC LIMIT 1), 0) AS LastBountyAmount,
         CASE WHEN rq.ViewCount = 0 THEN NULL ELSE rq.Score * 1.0 / rq.ViewCount END AS ScorePerView
  FROM recent_questions rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN top3_tags tt ON tt.QuestionId = rq.Id
  WHERE rq.ClosedDate IS NOT NULL
)
SELECT * FROM open_set
UNION ALL
SELECT * FROM closed_set
ORDER BY CreationDate DESC
LIMIT 400;