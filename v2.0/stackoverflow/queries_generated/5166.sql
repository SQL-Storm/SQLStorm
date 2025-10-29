-- {"query": "5166.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 582} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TagMentions AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.ViewCount) AS MaxViewsForTag
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
),
Enriched AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerDisplayName,
    tt.TagName,
    tt.TagQuestionCount,
    tt.AvgQuestionScore,
    tt.MaxViewsForTag
  FROM RecentTopQuestions r
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
  ) tt ON TRUE
  LEFT JOIN TagMentions tm ON tm.TagName = tt.TagName
  WHERE r.rn <= 5
)
SELECT
  e.PostId,
  e.Title,
  e.CreationDate,
  e.Score AS PostScore,
  e.ViewCount,
  e.OwnerUserId,
  e.OwnerDisplayName,
  e.TagName,
  e.TagQuestionCount,
  e.AvgQuestionScore,
  e.MaxViewsForTag,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = e.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2) AS Upvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3) AS Downvotes,
  (SELECT STRING_AGG(CONCAT_WS(':', v.VoteTypeId, v.CreationDate::text), ',')
     FROM Votes v WHERE v.PostId = e.PostId) AS VotesTimeline
FROM Enriched e
ORDER BY e.TagQuestionCount DESC, e.AvgQuestionScore DESC, e.MaxViewsForTag DESC
LIMIT 100;