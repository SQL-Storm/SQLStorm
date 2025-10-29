-- {"query": "5930.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 622}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.Reputation,
    u.DisplayName,
    COALESCE(a.Id, 0) AS AcceptedAnswerId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
tag_aggregates AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.Id AS PostId,
    p.ViewCount,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_counts AS (
  SELECT
    ta.TagName,
    COUNT(*) AS TagPostCount,
    SUM(COALESCE(ta.ViewCount, 0)) AS TagTotalViews,
    AVG(COALESCE(ta.Score, 0)) AS TagAverageScore
  FROM recent_questions rq
  JOIN tag_aggregates ta ON ta.PostId = rq.PostId
  GROUP BY ta.TagName
),
complex_edges AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Reputation,
    rq.DisplayName,
    rq.AcceptedAnswerId,
    rq.LastActivityDate,
    rq.rn,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId IN (2,3)) AS UpDownVotes
  FROM recent_questions rq
  WHERE rq.rn <= 100
),
open_tags AS (
  SELECT
    te.PostId,
    STRING_AGG(DISTINCT tc.TagName, ',') AS TagsForPost
  FROM tag_aggregates te
  JOIN tag_counts tc ON tc.TagName = te.TagName
  GROUP BY te.PostId
)
SELECT
  ce.PostId,
  ce.Title,
  ce.DisplayName AS Owner,
  ce.Reputation,
  ce.AcceptedAnswerId,
  ce.LastActivityDate,
  ce.CommentCount,
  ce.UpDownVotes,
  ot.TagsForPost,
  qc.TagPostCount,
  qc.TagTotalViews,
  qc.TagAverageScore
FROM complex_edges ce
LEFT JOIN open_tags ot ON ot.PostId = ce.PostId
LEFT JOIN LATERAL (
  -- pick the first word from the title and join to tag_counts if it matches a tag name
  SELECT tc.*
  FROM (
    SELECT unnest(string_to_array(substr(ce.Title, 1, 300), ' ')) AS word
  ) w
  JOIN tag_counts tc ON tc.TagName = w.word
  LIMIT 1
) qc ON TRUE
ORDER BY ce.rn
OFFSET 0 ROWS FETCH FIRST 100 ROWS ONLY;