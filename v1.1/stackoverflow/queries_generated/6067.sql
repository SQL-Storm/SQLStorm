-- {"query": "6067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1091} 
WITH
-- 1) Top rewarding users by total bounty and upvotes with windowing
TopUsers as (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    SUM(v.BountyAmount) OVER (PARTITION BY u.Id) AS TotalBountyEarned,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) OVER (PARTITION BY u.Id) AS BountyStartAmount,
    ROW_NUMBER() OVER (ORDER BY SUM(v.BountyAmount) OVER (PARTITION BY u.Id) DESC, u.Reputation DESC, u.Id) AS rn
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (8,9,10)
),
-- 2) Posts with complex predicates and calculated fields
PostAnalytics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditDate,
    -- derived metrics
    CASE
      WHEN p.ViewCount > 1000 THEN 'hot'
      WHEN p.ViewCount BETWEEN 100 AND 999 THEN 'warm'
      ELSE 'cool'
    END AS ViewTier,
    COALESCE(ARRAY_LENGTH(string_to_array(p.Tags, '><')), 0) AS TagCount,
    -- NULL-safe boolean test: is closed?
    CASE WHEN p.ClosedDate IS NULL THEN false ELSE true END AS IsClosed
  FROM Posts p
),
-- 3) Correlated subquery: latest comment per post by any user and by Owner
LatestComment AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.CreationDate,
    c.Text
  FROM Comments c
  JOIN (
    SELECT PostId, MAX(CreationDate) AS MaxDate
    FROM Comments
    GROUP BY PostId
  ) m ON m.PostId = c.PostId AND m.MaxDate = c.CreationDate
),
-- 4) Major join graph: posts joined to related posts via PostLinks (including duplicates)
LinkedPosts AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    p1.Score AS PostScore,
    p2.Score AS RelatedPostScore,
    p1.OwnerUserId AS PostOwner,
    p2.OwnerUserId AS RelatedOwner
  FROM PostLinks pl
  JOIN Posts p1 ON pl.PostId = p1.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
-- 5) Windowed ranking: top 5 similar posts per post by score difference
SimilarRank AS (
  SELECT
    lp.PostId,
    lp.RelatedPostId,
    lp.PostScore,
    lp.RelatedPostScore,
    ABS(lp.PostScore - lp.RelatedPostScore) AS ScoreDiff,
    ROW_NUMBER() OVER (
      PARTITION BY lp.PostId
      ORDER BY ABS(lp.PostScore - lp.RelatedPostScore) ASC, lp.RelatedPostScore DESC
    ) AS rk
  FROM LinkedPosts lp
),
-- 6) Final selection with complex predicates including string and NULL handling
Final as (
  SELECT
    ta.PostId,
    ta.Title,
    ta.Tags,
    ta.Score,
    ta.ViewCount,
    ta.CreationDate,
    ta.LastActivityDate,
    ta.IsClosed,
    ta.ViewTier,
    ta.TagCount,
    lc.CommentId AS LatestCommentId,
    lc.UserId AS LatestCommentUserId,
    lc.Text AS LatestCommentText,
    sr.RelatedPostId,
    sr.RelatedPostScore,
    u.Id AS AuthorId,
    u.DisplayName AS AuthorName,
    u.Reputation,
    u.AccountId,
    -- scalar subquery: average score of posts by author
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgAuthorPostScore
  FROM PostAnalytics ta
  LEFT JOIN LatestComment lc ON lc.PostId = ta.PostId
  LEFT JOIN Users u ON u.Id = ta.OwnerUserId
  LEFT JOIN SimilarRank sr ON sr.PostId = ta.PostId AND sr.rk = 1 -- best similar post
  WHERE
    ta.ViewCount >= 0 -- explicit non-null-ish predicate
    AND (ta.IsClosed = false OR ta.IsClosed IS NULL)
    AND (ta.TagCount > 0 OR ta.Title ILIKE ANY (ARRAY['%SQL%', '%Benchmark%', '%Performance%']))
)
SELECT
  *
FROM Final
ORDER BY
  AvgAuthorPostScore DESC NULLS LAST,
  AuthorName ASC
LIMIT 100;