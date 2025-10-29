-- {"query": "5213.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 930} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    u.Reputation,
    u.DisplayName AS OwnerName,
    u.AccountId,
    -- window: compute running total of upvotes on related posts via self-join
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS UpvotesByOwnerToDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  -- include tags/filters for interesting correlation
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
correlated AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.Reputation,
    rp.UpvotesByOwnerToDate,
    -- extra metrics: number of linked posts of type Duplicate or Linked
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId IN (1,3) THEN pl.Id END) OVER (PARTITION BY rp.PostId) AS LinkCount,
    MAX(CASE WHEN v2.VoteTypeId = 2 THEN v2.BountyAmount ELSE 0 END) OVER (PARTITION BY rp.PostId) AS MaxUpvoteBounty
  FROM ranked_posts rp
  LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
  LEFT JOIN Votes v2 ON v2.PostId = rp.PostId
  GROUP BY
    rp.PostId, rp.Title, rp.Tags, rp.Score, rp.ViewCount, rp.CreationDate,
    rp.LastActivityDate, rp.OwnerUserId, rp.OwnerName, rp.Reputation, rp.UpvotesByOwnerToDate
),
cte_hist AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.OwnerName,
    c.Reputation,
    c.UpvotesByOwnerToDate,
    c.LinkCount,
    c.MaxUpvoteBounty,
    -- correlated subquery: number of comments on this post with positive text sentiment indicator (simulated)
    (SELECT COUNT(*) FROM Comments co
     WHERE co.PostId = c.PostId
       AND co.Text LIKE '%good%' OR co.Text LIKE '%great%' ) AS PositiveCommentCount
  FROM correlated c
),
final_result AS (
  SELECT
    th.PostId,
    th.Title,
    th.Tags,
    th.Score,
    th.ViewCount,
    th.CreationDate,
    th.LastActivityDate,
    th.OwnerUserId,
    th.OwnerName,
    th.Reputation,
    th.UpvotesByOwnerToDate,
    th.LinkCount,
    th.MaxUpvoteBounty,
    th.PositiveCommentCount,
    -- complex expression: compute a derived "activity score" combining several factors
    (th.Score * 2 + th.ViewCount / NULLIF(th.PositiveCommentCount + 1, 0) + th.UpvotesByOwnerToDate) AS ActivityScore
  FROM cte_hist th
)
SELECT
  fr.PostId,
  fr.Title,
  fr.Tags,
  fr.Score,
  fr.ViewCount,
  fr.CreationDate,
  fr.LastActivityDate,
  fr.OwnerUserId,
  fr.OwnerName,
  fr.Reputation,
  fr.UpvotesByOwnerToDate,
  fr.LinkCount,
  fr.MaxUpvoteBounty,
  fr.PositiveCommentCount,
  fr.ActivityScore
FROM final_result fr
ORDER BY fr.ActivityScore DESC
LIMIT 100;