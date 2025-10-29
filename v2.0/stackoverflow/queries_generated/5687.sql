-- {"query": "5687.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 862} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.WebsiteUrl,
    u.EmailHash,
    u.AccountId,
    -- compute a complex score using window function over time
    SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_score,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY 
        p.Score * CASE WHEN p.Tags LIKE '%<sql>%'
                       THEN 2
                       ELSE 1
                  END +
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate))/86400.0 DESC
    ) AS rn,
    -- tag-based normalization
    CASE
      WHEN p.Tags IS NULL THEN NULL
      ELSE (SELECT AVG(t2.Count) FROM Tags t2 WHERE t2.TagName = ANY(string_to_array(replace(REPLACE(p.Tags, '<',''), '>', ''), '><')))
    END AS avg_tag_count
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
filtered AS (
  SELECT
    r.*,
    -- correlated subquery: count comments per post with dynamic threshold
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id AND c.Score > 0) AS positive_comments,
    -- correlated subquery: latest vote timestamp for this post
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = r.Id) AS last_vote_date
  FROM ranked_posts r
  WHERE r.cumulative_score > 1000
    AND (r.LastActivityDate IS NOT NULL AND r.LastActivityDate > r.CreationDate - INTERVAL '180 days')
),
complex AS (
  SELECT
    f.*,
    -- left join to PostLinks to fetch related posts and their types
    pl.RelatedPostId,
    pl2.PostTypeId AS RelatedPostTypeId,
    -- compute a derived bool: is hot if views weighted by score exceed a threshold
    CASE
      WHEN f.ViewCount * 0.5 + f.Score * 20 > 5000 THEN TRUE
      ELSE FALSE
    END AS IsHot
  FROM filtered f
  LEFT JOIN PostLinks pl ON pl.PostId = f.Id
  LEFT JOIN Posts pl2 ON pl.RelatedPostId = pl2.Id
)
SELECT
  c.Id,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.Tags,
  c.LastActivityDate,
  c.PostTypeId,
  c.AcceptedAnswerId,
  c.ParentId,
  c.LastEditDate,
  c.CommentCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.Reputation,
  c.DisplayName,
  c.LastAccessDate,
  c.Location,
  c.Views,
  c.UpVotes,
  c.DownVotes,
  c.WebsiteUrl,
  c.EmailHash,
  c.AccountId,
  c.cumulative_score,
  c.rn,
  c.avg_tag_count,
  c.positive_comments,
  c.last_vote_date,
  c.RelatedPostId,
  c.RelatedPostTypeId,
  c.IsHot
FROM complex c
ORDER BY c.IsHot DESC, c.cumulative_score DESC, c.LastActivityDate DESC
LIMIT 200;