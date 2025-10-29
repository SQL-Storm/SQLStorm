-- {"query": "5594.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 887} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    COALESCE(p.Body, '') AS Body,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    -- windowed metrics: running rank by score within day
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE) ORDER BY p.Score DESC, p.ViewCount DESC) AS DayRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesFromVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesFromVotes
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.LastActivityDate, p.ViewCount, p.Score
),
tag_mentions AS (
  SELECT
    p.Id AS PostId,
    unn.Tag AS TagName,
    COUNT(*) AS TagMentionCount
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) t
  JOIN LATERAL (
    SELECT trim(t.Tag) AS Tag
  ) unn ON true
  GROUP BY p.Id, unn.Tag
),
complex_filter AS (
  SELECT
    t.PostId,
    t.Title,
    t.OwnerName,
    t.Reputation,
    t.OwnerCreationDate,
    t.OwnerLastAccessDate,
    t.DayRank,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score AS PostScore,
    ra.CommentCount AS PostCommentCount,
    ra.UpvotesFromVotes,
    ra.DownvotesFromVotes,
    COALESCE(tb.TagMentionCount, 0) AS RelatedTagCount
  FROM top_questions t
  LEFT JOIN recent_activity ra ON ra.PostId = t.PostId
  LEFT JOIN tag_mentions tb ON tb.PostId = t.PostId
  WHERE t.DayRank <= 50
    AND COALESCE(ra.ViewCount, 0) > 100
    AND COALESCE(ra.PostCommentCount, 0) > 0
    -- complex predicate with NULL handling and computed expressions
    AND (t.Reputation IS NULL OR t.Reputation >= 100)
    AND (EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = t.OwnerUserId
        AND b.Class = 1
    ) OR t.Reputation >= 200)
)
SELECT
  cf.PostId,
  cf.Title,
  cf.OwnerName,
  cf.Reputation,
  cf.OwnerCreationDate,
  cf.OwnerLastAccessDate,
  cf.DayRank,
  cf.LastActivityDate,
  cf.ViewCount,
  cf.PostScore,
  cf.PostCommentCount,
  cf.UpvotesFromVotes,
  cf.DownvotesFromVotes,
  cf.RelatedTagCount,
  -- additional calculated field with string manipulation and NULL-safe logic
  CONCAT_WS(' | ', COALESCE(cf.Title, ''), COALESCE(cf.OwnerName, ''), CAST(cf.PostScore AS VARCHAR), COALESCE(cf.RelatedTagCount::text, '0')) AS BenchmarkSnapshot
FROM complex_filter cf
ORDER BY cf.DayRank, cf.LastActivityDate DESC
LIMIT 100;