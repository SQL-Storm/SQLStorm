-- {"query": "5677.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 890} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
),
recent_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 100
),
author_buckets AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    CASE
      WHEN u.Reputation < 1000 THEN 'Newbie'
      WHEN u.Reputation < 10000 THEN 'Rising'
      WHEN u.Reputation < 50000 THEN 'Desc'
      ELSE 'Veteran'
    END AS Tier
  FROM Users u
),
complex_filters AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.Tags,
    rp.PostTypeId,
    rp.FavoriteCount,
    rp.ContentLicense,
    ab.Tier,
    (CASE
       WHEN rp.ViewCount > 1000 THEN 1
       ELSE 0
     END) AS HighVisibilityFlag,
    (CASE
       WHEN rp.Score > 0 AND rp.AnswerCount > 0 THEN 1
       ELSE 0
     END) AS EngagedFlag,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.Id) AS LinkCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpVotesFromTable
  FROM ranked_posts rp
  LEFT JOIN author_buckets ab ON rp.OwnerUserId = ab.UserId
  WHERE
    rp.rn = 1
    AND rp.ViewCount >= 0
),
agg AS (
  SELECT
    cf.Id,
    cf.Title,
    cf.OwnerDisplayName,
    cf.Reputation,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.ViewCount,
    cf.Score,
    cf.AnswerCount,
    cf.CommentCount,
    cf.Tags,
    cf.PostTypeId,
    cf.FavoriteCount,
    cf.ContentLicense,
    cf.Tier,
    cf.HighVisibilityFlag,
    cf.EngagedFlag,
    cf.LinkCount,
    cf.UpVotesFromTable,
    -- window function: running total of UpVotesFromTable over LastActivityDate within each PostType
    SUM(cf.UpVotesFromTable) OVER (PARTITION BY cf.PostTypeId ORDER BY cf.LastActivityDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningUpvotes
  FROM complex_filters cf
)
SELECT
  a.Title,
  a.OwnerDisplayName,
  a.Tier,
  a.Reputation,
  a.CreationDate,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.AnswerCount,
  a.CommentCount,
  a.Tags,
  a.PostTypeId,
  a.FavoriteCount,
  a.ContentLicense,
  a.HighVisibilityFlag,
  a.EngagedFlag,
  a.LinkCount,
  a UpVotesFromTable,
  a.RunningUpvotes
FROM agg a
ORDER BY a.LastActivityDate DESC, a.RunningUpvotes DESC
LIMIT 200;