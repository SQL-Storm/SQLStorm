-- {"query": "5933.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1001} 
WITH qualified_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.Body,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
recent_activities AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY q.OwnerUserId
      ORDER BY q.LastActivityDate DESC
    ) AS rn_by_owner
  FROM qualified_questions q
  LEFT JOIN Posts p ON p.Id = q.PostId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
),
tag_impact AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score,
    ra.AnswerCount,
    ra.CommentCount,
    ra.Tags,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.Reputation,
    CASE
      WHEN ra.Tags ~ '\\<[^>]*\\>' THEN
        (SELECT STRING_AGG(t.TagName, ',')
         FROM unnest(string_to_array(substring(ra.Tags, 2, length(ra.Tags)-2), '><')) AS t(TagName)
         JOIN Tags tg ON lower(t.TagName) = lower(tg.TagName)
         WHERE tg.Count > 0)
      ELSE NULL
    END AS TagNames
  FROM recent_activities ra
  WHERE ra.rn_by_owner = 1
),
activity_summary AS (
  SELECT
    ta.PostId,
    ta.Title,
    ta.LastActivityDate,
    ta.ViewCount,
    ta.Score,
    ta.AnswerCount,
    ta.CommentCount,
    ta.Tags,
    ta.OwnerUserId,
    ta.OwnerDisplayName,
    ta.Reputation,
    ta.TagNames
  FROM tag_impact ta
)
SELECT
  ASOK.PostId AS "Post/QuestionID",
  ASOK.Title AS "QuestionTitle",
  ASOK.OwnerDisplayName AS "Owner",
  ASOK.Reputation AS "OwnerReputation",
  ASOK.LastActivityDate AS "LastActivity",
  ASOK.ViewCount AS "Views",
  ASOK.Score AS "Score",
  ASOK.AnswerCount AS "AnswerCount",
  ASOK.CommentCount AS "CommentCount",
  ASOK.Tags AS "Tags",
  COALESCE(ASOK.TagNames, ASOK.Tags) AS "TagNamesUsed",
  -- Window function example: running total of views per owner over time
  SUM(ASOK.ViewCount) OVER (
    PARTITION BY ASOK.OwnerUserId
    ORDER BY ASOK.LastActivityDate
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS "CumulativeViewsByOwner",
  -- Correlated subquery: count of posts by the owner in the last 30 days
  (
    SELECT COUNT(*) FROM Posts p2
    WHERE p2.OwnerUserId = ASOK.OwnerUserId
      AND p2.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
      AND p2.PostTypeId = 1
  ) AS "RecentPostsByOwner30d",
  -- Outer join example: fetch related posts via PostLinks of type 1 (Linked)
  COALESCE(lk.RelatedPostId, ASOK.PostId) AS "LinkedOrSelfPost",
  -- Complex predicate: posts with high engagement and not recently edited
  CASE
    WHEN ASOK.ViewCount > 1000 AND ASOK.Score > 5 AND (ASOK.LastActivityDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days')
      THEN true
    ELSE false
  END AS "HighEngagementOld",
  -- Null handling: determine if owner is Community (NULL OwnerUserId for some edges)
  CASE
    WHEN ASOK.OwnerUserId IS NULL THEN 'Unknown'
    WHEN ASOK.OwnerUserId = -1 THEN 'Community'
    ELSE 'Regular'
  END AS "OwnerType"
FROM activity_summary ASOK
LEFT JOIN PostLinks lk
  ON lk.PostId = ASOK.PostId
  AND lk.LinkTypeId = 1
ORDER BY ASOK.LastActivityDate DESC
LIMIT 100;