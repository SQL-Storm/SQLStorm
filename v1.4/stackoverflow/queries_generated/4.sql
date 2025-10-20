-- {"query": "4.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 769} 
WITH
-- sample recent activity per post with window functions
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
),
-- correlate with last editor info when available
LastEd AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.Score,
    ra.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    ra.LastActivityDate,
    le.DisplayName AS LastEditorDisplayName
  FROM RecentActivity ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
  LEFT JOIN Users le ON ra.LastEditorUserId = le.Id
  WHERE ra.rn = 1
),
-- compute advanced metrics per post using correlated subqueries
Metrics AS (
  SELECT
    la.PostId,
    la.Title,
    la.CreationDate,
    la.Score,
    la.ViewCount,
    la.OwnerDisplayName,
    la.LastActivityDate,
    la.LastEditorDisplayName,
    -- distinct counts of comments and answers
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = la.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Posts child WHERE child.ParentId = la.PostId AND child.PostTypeId = 2) AS AnswerCount,
    -- sum of upvotes minus downvotes from Votes for this post (excluding non-up/down types)
    (SELECT COALESCE(SUM(v.BountyAmount),0)
     FROM Votes v
     WHERE v.PostId = la.PostId AND v.VoteTypeId IN (2,3)) AS NetVotes
  FROM LastEd la
),
-- top k tags influence on score (via string processing) - using Tags table for count placeholder
TagInfluence AS (
  SELECT
    m.PostId,
    m.Title,
    m.CommentCount,
    m.AnswerCount,
    m.NetVotes,
    (SELECT STRING_AGG(t.TagName, ',') FROM Tags t
     JOIN Posts p ON p.Id = m.PostId
     WHERE p.Tags LIKE '%' || t.TagName || '%' OR t.TagName = ANY (string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))
     AS TagList
  FROM Metrics m
),
-- final selection with complex predicate and set-operation flavored logic
Final AS (
  SELECT
    ti.PostId,
    ti.Title,
    ti.CreationDate,
    ti.ViewCount,
    ti.Score,
    ti.CommentCount,
    ti.AnswerCount,
    ti.NetVotes,
    ti.TagList,
    ti.OwnerDisplayName,
    ti.LastEditorDisplayName,
    -- computed ranking expression with NULL-sensitive logic
    CASE
      WHEN ti.ViewCount IS NULL THEN 0
      ELSE (ti.ViewCount * 3) + (COALESCE(ti.Score,0) * 5) + (COALESCE(ti.CommentCount,0) * 7)
    END AS BenchmarkScore
  FROM TagInfluence ti
  WHERE
    -- complex predicate: recent activity within last 365 days and has at least one tag
    ti.CreationDate >= NOW() - INTERVAL '365 days'
    AND ti.TagList IS NOT NULL
  ORDER BY BenchmarkScore DESC
)
SELECT
  *
FROM Final
LIMIT 100;