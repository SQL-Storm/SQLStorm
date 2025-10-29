-- {"query": "5950.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 750} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
top_activity AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    u.Reputation,
    u.DisplayName,
    u.LastAccessDate,
    u.Location,
    v.TotalVotes
  FROM recent_questions rq
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS TotalVotes
    FROM Votes
    WHERE PostId IS NOT NULL
    GROUP BY PostId
  ) v ON v.PostId = rq.PostId
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
),
filtered AS (
  SELECT
    ta.PostId,
    ta.Title,
    ta.Tags,
    ta.CreationDate,
    ta.Score,
    ta.ViewCount,
    ta.OwnerUserId,
    ta.LastActivityDate,
    ta.CommentCount,
    ta.AnswerCount,
    ta.Reputation,
    ta.DisplayName,
    ta.LastAccessDate,
    ta.Location,
    ta.TotalVotes,
    COALESCE((SELECT STRING_AGG(CAST(bt.Class AS TEXT), ',')
              FROM Badges bt
              WHERE bt.UserId = ta.OwnerUserId), '') AS BadgeClasses,
    -- complex predicate: posts with high activity and user reputation above threshold and many badges
    CASE
      WHEN ta.ViewCount > 1000 AND ta.TotalVotes > 20 THEN 'Hot'
      WHEN ta.Reputation >= 10000 THEN 'Influencer'
      ELSE 'Regular'
    END AS Category,
    -- window function: rank within category by LastActivityDate
    ROW_NUMBER() OVER (PARTITION BY
      CASE
        WHEN ta.ViewCount > 1000 AND ta.TotalVotes > 20 THEN 'Hot'
        WHEN ta.Reputation >= 10000 THEN 'Influencer'
        ELSE 'Regular'
      END
    ORDER BY ta.LastActivityDate DESC) AS CategoryRank
  FROM top_activity ta
)
SELECT
  pth.PostId,
  pth.Title,
  pth.Tags,
  pth.CreationDate,
  pth.Score,
  pth.ViewCount,
  pth.OwnerUserId,
  pth.LastActivityDate,
  pth.CommentCount,
  pth.AnswerCount,
  pth.Reputation,
  pth.DisplayName,
  pth.LastAccessDate,
  pth.Location,
  pth.TotalVotes,
  pth.BadgeClasses,
  pth.Category,
  pth.CategoryRank,
  -- an outer join to include related posts via PostLinks (e.g., duplicates or linked posts)
  pl.RelatedPostId,
  pl.LinkTypeId,
  lt.Name AS LinkTypeName
FROM filtered pth
LEFT JOIN PostLinks pl ON pl.PostId = pth.PostId
LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
LEFT JOIN Posts r ON r.Id = pl.RelatedPostId
ORDER BY pth.Category, pth.LastActivityDate DESC
LIMIT 100;