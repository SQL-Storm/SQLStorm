-- {"query": "262.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5929} 
WITH
tagged_posts AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         trim(s.tg) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''), 2, GREATEST(length(coalesce(p.Tags,'')) - 2,0)), '><')) AS tg
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
user_post_counts AS (
  SELECT u.Id AS UserId, u.DisplayName,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
         COUNT(p.Id) AS TotalPosts,
         SUM(p.Score) AS TotalScore,
         AVG(p.Score) AS AvgScore,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
         COUNT(DISTINCT tp.Tag) AS DistinctTags
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN tagged_posts tp ON tp.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
badge_summary AS (
  SELECT UserId,
         COUNT(*) AS BadgesTotal,
         SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS Gold,
         SUM(CASE WHEN Class=2 THEN 1 ELSE 0 END) AS Silver,
         SUM(CASE WHEN Class=3 THEN 1 ELSE 0 END) AS Bronze,
         SUM(CASE WHEN TagBased THEN 1 ELSE 0 END) AS TagBadges
  FROM Badges
  GROUP BY UserId
),
post_votes AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedCount,
         COUNT(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
post_enriched AS (
  SELECT p.*,
         COALESCE(pv.UpVotes,0) AS UpVotes,
         COALESCE(pv.DownVotes,0) AS DownVotes,
         COALESCE(pv.AcceptedCount,0) AS AcceptedCount,
         COALESCE(pv.TotalVotes,0) AS TotalVotes,
         EXTRACT(EPOCH FROM (current_timestamp - p.CreationDate))/86400.0 AS AgeDays,
         CASE WHEN p.ViewCount IS NULL OR p.ViewCount=0 THEN NULL ELSE (p.Score::numeric / NULLIF(p.ViewCount,0)) END AS ScorePerView
  FROM Posts p
  LEFT JOIN post_votes pv ON pv.PostId = p.Id
),
top_posts_per_tag AS (
  SELECT p.Id, p.Title, p.OwnerUserId, t.Tag, p.Score, p.ViewCount,
         ROW_NUMBER() OVER (PARTITION BY t.Tag ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate) AS TagRank,
         RANK() OVER (ORDER BY p.Score DESC NULLS LAST) AS GlobalRank
  FROM Posts p
  JOIN tagged_posts t ON t.PostId = p.Id
),
duplicate_links AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
user_influence AS (
  SELECT upc.UserId,
         upc.DisplayName,
         upc.Questions,
         upc.Answers,
         upc.TotalPosts,
         COALESCE(b.BadgesTotal,0) AS BadgesTotal,
         COALESCE(b.Gold,0) AS Gold,
         COALESCE(b.Silver,0) AS Silver,
         COALESCE(b.Bronze,0) AS Bronze,
         COALESCE(upc.TotalScore,0) AS TotalScore,
         upc.MedianScore,
         upc.AvgScore,
         upc.DistinctTags,
         ((upc.Answers::numeric * 2)
           + (upc.Questions::numeric)
           + sqrt(GREATEST(COALESCE(upc.TotalScore,0),0)::numeric)
           + (COALESCE(b.BadgesTotal,0) * 1.5)
           + CASE WHEN upc.DistinctTags > 0 THEN ln(upc.DistinctTags) ELSE 0 END
         ) * (1 + COALESCE(NULLIF(upc.MedianScore,0),0) / GREATEST(COALESCE(upc.AvgScore,1),1)) AS InfluenceScore,
         (SELECT tg.Tag FROM (
             SELECT tg.Tag, COUNT(*) AS cnt
             FROM tagged_posts tg
             JOIN Posts p2 ON p2.Id = tg.PostId
             WHERE p2.OwnerUserId = upc.UserId
             GROUP BY tg.Tag
             ORDER BY cnt DESC NULLS LAST, tg.Tag
             LIMIT 1
         ) tg) AS TopTag,
         ((SELECT COUNT(*) FROM duplicate_links dl JOIN Posts pp ON pp.Id = dl.PostId WHERE pp.OwnerUserId = upc.UserId)
          +
          (SELECT COUNT(*) FROM duplicate_links dl JOIN Posts pp2 ON pp2.Id = dl.RelatedPostId WHERE pp2.OwnerUserId = upc.UserId)
         ) AS DuplicateMentions
  FROM user_post_counts upc
  LEFT JOIN badge_summary b ON b.UserId = upc.UserId
),
selected_users AS (
  SELECT ui.*,
         ROW_NUMBER() OVER (ORDER BY ui.InfluenceScore DESC NULLS LAST, ui.TotalPosts DESC) AS InfluenceRank
  FROM user_influence ui
  WHERE ui.TotalPosts > 0
),
user_result AS (
  SELECT
    'user'::text AS entity_type,
    u.UserId::int AS entity_id,
    u.DisplayName::text AS name,
    u.TopTag::text AS primary_tag,
    u.Questions::int AS Questions,
    u.Answers::int AS Answers,
    u.TotalPosts::int AS TotalPosts,
    u.BadgesTotal::int AS BadgesTotal,
    u.Gold::int AS Gold,
    u.Silver::int AS Silver,
    u.Bronze::int AS Bronze,
    u.TotalScore::numeric AS TotalScore,
    u.MedianScore::numeric AS MedianScore,
    u.DistinctTags::int AS DistinctTags,
    u.DuplicateMentions::int AS DuplicateMentions,
    ROUND(u.InfluenceScore::numeric,4) AS influence,
    u.InfluenceRank::int AS rank_order,
    NULL::text AS tag_info
  FROM selected_users u
  WHERE u.InfluenceRank <= 100
),
tag_result AS (
  SELECT
    'tag'::text AS entity_type,
    NULL::int AS entity_id,
    t.Tag::text AS name,
    NULL::text AS primary_tag,
    t.QCount::int AS Questions,
    NULL::int AS Answers,
    t.QCount::int AS TotalPosts,
    NULL::int AS BadgesTotal,
    NULL::int AS Gold,
    NULL::int AS Silver,
    NULL::int AS Bronze,
    t.QScoreSum::numeric AS TotalScore,
    t.QScoreAvg::numeric AS MedianScore,
    NULL::int AS DistinctTags,
    NULL::int AS DuplicateMentions,
    ROUND((COALESCE(t.QScoreSum,0) * 0.6 + COALESCE(t.QViews,0) * 0.1 + COALESCE(t.UniqueAskers,0) * 0.3)::numeric,4) AS influence,
    ROW_NUMBER() OVER (ORDER BY (COALESCE(t.QScoreSum,0) * 0.6 + COALESCE(t.QViews,0) * 0.1 + COALESCE(t.UniqueAskers,0) * 0.3) DESC) AS rank_order,
    CONCAT('tag:', t.Tag, '|q=', t.QCount, '|avg=', ROUND(COALESCE(t.QScoreAvg,0)::numeric,2)) AS tag_info
  FROM (
    SELECT tp.Tag, COUNT(*) AS QCount, SUM(tp.Score) AS QScoreSum, AVG(tp.Score) AS QScoreAvg, SUM(tp.ViewCount) AS QViews, COUNT(DISTINCT tp.OwnerUserId) AS UniqueAskers
    FROM tagged_posts tp
    JOIN Posts p ON p.Id = tp.PostId
    GROUP BY tp.Tag
  ) t
  WHERE t.QCount >= 5
),
combined AS (
  SELECT * FROM user_result
  UNION ALL
  SELECT * FROM tag_result
),
filtered AS (
  SELECT * FROM combined
  EXCEPT
  SELECT * FROM combined WHERE influence < 1
)
SELECT *
FROM filtered
ORDER BY entity_type DESC, influence DESC, rank_order ASC
LIMIT 200;