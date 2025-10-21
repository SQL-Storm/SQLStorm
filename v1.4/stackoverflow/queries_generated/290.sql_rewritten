-- {"query": "290.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 15525} 
WITH
base_posts AS (
  SELECT
    p.Id,
    COALESCE(p.Title, '') AS Title,
    p.Tags,
    p.OwnerUserId,
    COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
    CASE
      WHEN p.Tags IS NULL THEN 0
      ELSE (SELECT COUNT(*) FROM regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS t)
    END AS TagCount,
    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
    (SELECT pl.RelatedPostId
     FROM PostLinks pl
     WHERE pl.PostId = p.Id
     ORDER BY pl.CreationDate DESC
     LIMIT 1) AS LatestLinkedPostId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
  GROUP BY p.Id, p.Title, p.Tags, p.OwnerUserId, u.DisplayName, p.LastActivityDate, p.Score, p.ViewCount, p.CommentCount
),
scored AS (
  SELECT
    bp.*,
    (bp.Score::numeric
     + bp.UpVotes::numeric * 4
     - bp.DownVotes::numeric * 2
     + bp.ViewCount::numeric * 0.1
     + bp.TagCount::numeric * 0.5) AS CompositeScore,
    LOWER(REGEXP_REPLACE(COALESCE(bp.Title, ''), '[^a-zA-Z0-9]+', '-', 'g')) AS TitleSlug,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = bp.OwnerUserId AND b.Class = 1) AS GoldBadges
  FROM base_posts bp
),
ranked AS (
  SELECT
    s.*,
    ROW_NUMBER() OVER (
      PARTITION BY OwnerUserId
      ORDER BY CompositeScore DESC, LastActivityDate DESC
    ) AS rn
  FROM scored s
),
top5 AS (
  SELECT
    Id, Title, TitleSlug, Tags, OwnerUserId, OwnerDisplayName, LastActivityDate,
    Score, ViewCount, CommentCount, UpVotes, DownVotes, TagCount, GoldBadges,
    LastCommentDate, LatestLinkedPostId, CompositeScore
  FROM ranked
  WHERE rn <= 5
),
tail_alt AS (
  SELECT
    p.Id,
    COALESCE(p.Title, '') AS Title,
    LOWER(REGEXP_REPLACE(COALESCE(p.Title, ''), '[^a-zA-Z0-9]+', '-', 'g')) AS TitleSlug,
    p.Tags,
    p.OwnerUserId,
    COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
     FROM Votes v
     WHERE v.PostId = p.Id) AS UpVotes,
    (SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
     FROM Votes v
     WHERE v.PostId = p.Id) AS DownVotes,
    CASE
      WHEN p.Tags IS NULL THEN 0
      ELSE (SELECT COUNT(*) FROM regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS t)
    END AS TagCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
    (SELECT pl.RelatedPostId
     FROM PostLinks pl
     WHERE pl.PostId = p.Id
     ORDER BY pl.CreationDate DESC
     LIMIT 1) AS LatestLinkedPostId,
    (COALESCE(p.Score,0)::numeric
     + COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id),0)::numeric * 4
     - COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id),0)::numeric * 2
     + COALESCE(p.ViewCount,0)::numeric * 0.1
     + COALESCE((SELECT COUNT(*) FROM regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><')),0)::numeric * 0.5) AS CompositeScore
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    AND (CASE
           WHEN p.Tags IS NULL THEN 0
           ELSE (SELECT COUNT(*) FROM regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS t)
         END) > 2
),
union_all AS (
  SELECT Id, Title, TitleSlug, Tags, OwnerUserId, OwnerDisplayName, LastActivityDate,
         Score, ViewCount, CommentCount, UpVotes, DownVotes, TagCount, GoldBadges,
         LastCommentDate, LatestLinkedPostId, CompositeScore
  FROM top5
  UNION ALL
  SELECT Id, Title, TitleSlug, Tags, OwnerUserId, OwnerDisplayName, LastActivityDate,
         Score, ViewCount, CommentCount, UpVotes, DownVotes, TagCount, GoldBadges,
         LastCommentDate, LatestLinkedPostId, CompositeScore
  FROM tail_alt
),
final AS (
  SELECT *
  FROM union_all
  ORDER BY CompositeScore DESC
  LIMIT 100
)
SELECT *
FROM final
ORDER BY CompositeScore DESC, LastActivityDate DESC;