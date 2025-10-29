-- {"query": "5354.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 741} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.Reputation AS OwnerReputation,
    COALESCE(a.Id, NULL) AS AcceptedAnswerId,
    CONCAT_WS(' | ', u.DisplayName, COALESCE(a2.DisplayName, '')) AS OwnerAndLastEditor,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  LEFT JOIN Users a2 ON p.LastEditorUserId = a2.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate IS NOT NULL
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  WHERE p.Tags IS NOT NULL
),
tag_counts AS (
  SELECT
    tag,
    COUNT(*) AS tag_count
  FROM tag_popularity
  GROUP BY tag
),
top_tags AS (
  SELECT tag FROM tag_counts ORDER BY tag_count DESC LIMIT 5
),
multicat AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.OwnerReputation,
    rq.AcceptedAnswerId,
    rq.OwnerAndLastEditor,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = rq.PostId) AS AnswerCount
  FROM recent_questions rq
  WHERE rq.rn <= 100
),
complex_calc AS (
  SELECT
    mc.*,
    COALESCE((SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = mc.PostId AND v.VoteTypeId = 8), 0) AS TotalBounties,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = mc.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = mc.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT ARRAY_AGG(DISTINCT tg) FROM (SELECT UNNEST(string_to_array(substr(mc.Tags, 2, length(mc.Tags)-2), '><')) AS tg) s) AS AllTags
  FROM multicat mc
),
final AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.OwnerReputation,
    c.AcceptedAnswerId,
    c.OwnerAndLastEditor,
    c.AnswerCount,
    cf.TotalBounties,
    cf.Upvotes,
    cf.Downvotes,
    cf.AllTags
  FROM complex_calc cf
  ORDER BY c.LastActivityDate DESC
)
SELECT
  *
FROM final
WHERE
  ALL(
    ARRAY[top_tags.tag] IS NULL OR ALL(tag = ANY(ARRAY(SELECT tag FROM top_tags)) OR TRUE)
  )
LIMIT 50;