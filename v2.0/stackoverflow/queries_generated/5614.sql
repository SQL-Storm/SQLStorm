-- {"query": "5614.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 918} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(b.TotalBadges, 0) AS OwnerBadges,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
cte_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
cte_top_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUses,
    MAX(t.Count) AS TagCountSnapshot
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
  ORDER BY TagUses DESC
  LIMIT 10
),
recent_cross_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1,3) -- Linked and Duplicate
    AND pl.CreationDate >= NOW() - INTERVAL '180 days'
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '180 days'
),
filtered AS (
  SELECT rp.*
  FROM ranked_posts rp
  WHERE rp.rn = 1
    AND rp.PostTypeId = 1 -- Focus on questions
    AND rp.CreateDate IS NULL
)
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerDisplayName,
  rp.OwnerReputation,
  rp.OwnerBadges,
  rp.Tags,
  rp.AnswerCount,
  rp.CommentCount,
  rp.LastActivityDate,
  uad.TotalViews AS OwnerTotalViews,
  ttt.TagName AS TopTag,
  (SELECT MAX(CreationDate) FROM PostHistory ph WHERE ph.PostId = rp.PostId) AS LastEdited,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountAll,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpvotesLast180,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownvotesLast180,
  (SELECT STRING_AGG(CAST(v.VoteTypeId AS varchar), ',') FROM Votes v WHERE v.PostId = rp.PostId AND v.CreationDate >= NOW() - INTERVAL '90 days') AS RecentVoteTypes,
  (SELECT STRING_AGG(CONCAT('Tag:', t.TagName), '|') 
     FROM Tags t WHERE t.Id IN (SELECT UNNEST(string_to_array(rp.Tags, '>'))) ) AS TagFragments
FROM
  Posts rp
  LEFT JOIN cte_user_activity uad ON rp.OwnerUserId = uad.UserId
  LEFT JOIN cte_top_tags ttt ON true
WHERE
  rp.Id = rp.Id
ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CreationDate ASC
LIMIT 100;