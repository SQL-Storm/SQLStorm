-- {"query": "5864.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 871} 
WITH
  -- recent activity per post with various joins
  RecentActivity AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      COALESCE(p.Tags, '') AS TagsRaw,
      CASE
        WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
        WHEN u.DisplayName IS NOT NULL THEN u.DisplayName
        ELSE p.OwnerDisplayName
      END AS OwnerName,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- questions
  ),
  -- correlate with latest comment and latest vote types
  LatestInteractions AS (
    SELECT
      ra.PostId,
      MAX(c.CreationDate) AS LastCommentDate,
      MAX(v.CreationDate) AS LastVoteDate,
      MAX(v.BountyAmount) AS MaxBounty
    FROM RecentActivity ra
    LEFT JOIN Comments c ON c.PostId = ra.PostId
    LEFT JOIN Votes v ON v.PostId = ra.PostId
    GROUP BY ra.PostId
  ),
  -- gather tag and relation data with joins to Tag wiki/excerpts
  TagInfo AS (
    SELECT
      t.Id AS TagId,
      t.TagName,
      t.Count,
      t.ExcerptPostId,
      t.WikiPostId
    FROM Tags t
  ),
  -- compute a complex boolean predicate and string expressions
  Computed AS (
    SELECT
      ra.PostId,
      ra.Title,
      ra.CreationDate,
      ra.LastActivityDate,
      ra.Score,
      ra.ViewCount,
      ra.OwnerName,
      ra.TagsRaw,
      CASE
        WHEN ra.Score > 0 AND ra.ViewCount > 1000 THEN true
        ELSE false
      END AS IsPopular,
      CASE
        WHEN ra.Title ILIKE '%performance%' OR ra.Title ILIKE '%benchmark%' THEN 'Benchmark'
        ELSE 'General'
      END AS Category,
      (CASE WHEN ra.OwnerName <> 'Anonymous' THEN ra.OwnerName ELSE 'Guest' END) AS DisplayNameAlias,
      CONCAT('["', REPLACE(ra.OwnerName, '"', '\"'), '"]') AS OwnerJson,
      CONCAT(ra.Title, ' - ', ra.TagsRaw) AS TitleWithTags
    FROM RecentActivity ra
  ),
  -- windowed ranking across posts by activity
  Ranked AS (
    SELECT
      c.*,
      ROW_NUMBER() OVER (PARTITION BY Category ORDER BY LastActivityDate DESC, Score DESC, ViewCount DESC) AS CategoryRank,
      DENSE_RANK() OVER (ORDER BY LastActivityDate DESC) AS OverallRank
    FROM Computed c
  ),
  -- set operation: union with a synthetic baseline to benchmark set ops
  Baseline AS (
    SELECT
      0 AS PostId,
      'Baseline' AS Title,
      cast('2024-10-01 12:34:56' as timestamp) AS CreationDate,
      cast('2024-10-01 12:34:56' as timestamp) AS LastActivityDate,
      0 AS Score,
      0 AS ViewCount,
      'System' AS OwnerName,
      '' AS TagsRaw,
      false AS IsPopular,
      'Benchmark' AS Category,
      'System' AS DisplayNameAlias,
      '[]' AS OwnerJson,
      '' AS TitleWithTags,
      0 AS CategoryRank,
      0 AS OverallRank
  ),
  -- final unionized result to exercise set operators and advanced predicates
  FinalUnion AS (
    SELECT * FROM Ranked
    UNION ALL
    SELECT * FROM Baseline
  )
SELECT
  PostId,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerName,
  TagsRaw,
  IsPopular,
  Category,
  DisplayNameAlias,
  OwnerJson,
  TitleWithTags,
  CategoryRank,
  OverallRank
FROM FinalUnion
ORDER BY OverallRank ASC NULLS LAST, CategoryRank ASC NULLS LAST
LIMIT 200;