-- {"query": "5109.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 705}
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount * 0.6 + p.Score * 1.2 DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnTagQuestion,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnTagQuestion
  FROM Tags t
  LEFT JOIN Posts q ON POSITION(t.TagName IN COALESCE(q.Tags, '')) > 0
  LEFT JOIN Votes v ON v.PostId = q.Id
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
),
HotQuestions AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.FavoriteCount,
    COUNT(v.Id) AS VoteCount
  FROM RecentPopularQuestions r
  LEFT JOIN Votes v ON v.PostId = r.QuestionId
  GROUP BY
    r.QuestionId, r.Title, r.Tags, r.CreationDate, r.Score, r.ViewCount, r.OwnerUserId, r.FavoriteCount
  HAVING COUNT(v.Id) > 5
)
SELECT
  h.QuestionId,
  h.Title,
  h.Tags,
  h.CreationDate,
  h.Score,
  h.ViewCount,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  h.FavoriteCount,
  ARRAY_AGG(DISTINCT ll.RelatedPostId) FILTER (WHERE ll.RelatedPostId IS NOT NULL) AS LinkedPostIds,
  ARRAY_AGG(DISTINCT t.TagName) AS DetectedTags,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = h.QuestionId) AS CommentCount,
  (SELECT STRING_AGG(co.Value, '; ')
     FROM (
       SELECT 'Upvotes' AS Name, CAST(SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END) AS VARCHAR) AS Value
       FROM Votes v2 WHERE v2.PostId = h.QuestionId
     ) co
  ) AS VoteSummary
FROM HotQuestions h
LEFT JOIN Users u ON u.Id = h.OwnerUserId
LEFT JOIN PostLinks ll ON ll.PostId = h.QuestionId
-- split tags from format like '<tag1><tag2>' into rows using standard SQL: trim angle brackets and split by comma via regexp_split_to_table for Postgres,
-- or emulate by replacing '><' with ',' and using string_to_array + unnest. Here use standard-compatible approach for Postgres and other systems:
LEFT JOIN LATERAL (
  SELECT distinct TRIM(BOTH '<>' FROM val) AS TagName
  FROM regexp_split_to_table(REPLACE(COALESCE(h.Tags, ''), '><', ','), ',') AS s(val)
) st ON st.TagName <> ''
LEFT JOIN Tags t ON t.TagName = st.TagName
GROUP BY
  h.QuestionId,
  h.Title,
  h.Tags,
  h.CreationDate,
  h.Score,
  h.ViewCount,
  u.DisplayName,
  u.Reputation,
  h.FavoriteCount
ORDER BY h.ViewCount DESC, h.Score DESC
LIMIT 100;