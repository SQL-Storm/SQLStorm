-- {"query": "5838.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1142} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
TaggedActivity AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.Reputation,
    rp.ViewCount,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.LastEditDate,
    rp.ContentLicense,
    CASE
      WHEN rp.PostTypeId = 1 THEN 1
      ELSE 0
    END AS IsQuestion,
    COALESCE(tv.UpModCount, 0) AS UpModCount,
    COALESCE(tv.DownModCount, 0) AS DownModCount,
    COALESCE(bd.GoldCount, 0) AS GoldBadges,
    COALESCE(bd.SilverCount, 0) AS SilverBadges
  FROM RankedPosts rp
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) tv ON rp.Id = tv.PostId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldCount
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) bd ON rp.OwnerUserId = bd.UserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS SilverCount
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
  ) sd ON rp.OwnerUserId = sd.UserId
  WHERE rp.CreationDate >= NOW() - INTERVAL '365 days'
),
ComplexFilters AS (
  SELECT
    ta.*,
    -- Correlated subquery: count of related posts linked as duplicates to this post
    (
      SELECT COUNT(*) FROM PostLinks pl
      WHERE pl.PostId = ta.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinkCount,
    -- Window function: rank posts by LastActivityDate per owner
    ROW_NUMBER() OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.LastActivityDate DESC) AS OwnerPostRank
  FROM TaggedActivity ta
),
PerformanceBench AS (
  SELECT
    cf.Id,
    cf.Title,
    cf.PostTypeId,
    cf.OwnerUserId,
    cf.OwnerName,
    cf.Reputation,
    cf.ViewCount,
    cf.Tags,
    cf.AnswerCount,
    cf.CommentCount,
    cf.FavoriteCount,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.LastEditDate,
    cf.ContentLicense,
    cf.IsQuestion,
    cf.UpModCount,
    cf.DownModCount,
    cf.GoldBadges,
    cf.SilverBadges,
    cf.DuplicateLinkCount,
    cf.OwnerPostRank,
    -- Computed expression: engagement score combining various metrics
    (cf.ViewCount * 0.5 + cf.AnswerCount * 30 + cf.UpModCount * 15 - cf.DownModCount * 5) AS EngagementScore,
    -- Complex predicate example:
    CASE
      WHEN cf.IsQuestion = 1 AND cf.AnswerCount > 0 THEN 'Question with answers'
      WHEN cf.IsQuestion = 0 THEN 'Answer or other'
      ELSE 'Other'
    END AS CategoryLabel,
    -- String expression: normalized lowercased title for benchmarking
    LOWER(REGEXP_REPLACE(cf.Title, '[^a-zA-Z0-9 ]', '', 'g')) AS NormalizedTitle
  FROM ComplexFilters cf
)
SELECT
  pb.Id,
  pb.Title,
  pb.PostTypeId,
  pb.OwnerUserId,
  pb.OwnerName,
  pb.Reputation,
  pb.ViewCount,
  pb.Tags,
  pb.AnswerCount,
  pb.CommentCount,
  pb.FavoriteCount,
  pb.CreationDate,
  pb.LastActivityDate,
  pb.LastEditDate,
  pb.ContentLicense,
  pb.IsQuestion,
  pb.UpModCount,
  pb.DownModCount,
  pb.GoldBadges,
  pb.SilverBadges,
  pb.DuplicateLinkCount,
  pb.OwnerPostRank,
  pb.EngagementScore,
  pb.CategoryLabel,
  pb.NormalizedTitle
FROM PerformanceBench pb
WHERE pb.EngagementScore > 100
ORDER BY pb.EngagementScore DESC
LIMIT 100
OFFSET 0;