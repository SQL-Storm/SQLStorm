-- {"query": "22034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 759} 

WITH parsed_tags AS (
  SELECT 
    Id, 
    trim(unnest(string_to_array(substring(coalesce(Tags, ''), 2, length(coalesce(Tags, ''))-2), '><'))) AS tag
  FROM Posts
  WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
tag_stats AS (
  SELECT 
    tag, 
    COUNT(*) AS post_count
  FROM parsed_tags
  GROUP BY tag
),
user_engagement AS (
  SELECT 
    u.Id AS UserId,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(coalesce(v.Score, 0)) AS total_vote_score,
    COUNT(CASE WHEN b.Name LIKE '%Gold%' THEN 1 END) AS gold_badges
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
post_details AS (
  SELECT 
    p.Id,
    p.Title,
    p.Score,
    COUNT(pl.RelatedPostId) AS link_count,
    COUNT(c.Id) AS high_score_comments
  FROM Posts p
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score > 10
  WHERE p.PostTypeId = 1
    AND EXISTS (
      SELECT 1 
      FROM PostHistory ph 
      WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edit types
    )
  GROUP BY p.Id, p.Title, p.Score
),
enriched_posts AS (
  SELECT 
    pd.*,
    pt.tag,
    t.post_count AS tag_popularity,
    ue.total_vote_score,
    ue.gold_badges,
    SUM(CASE WHEN t.post_count > 100 THEN pd.Score ELSE 0 END) OVER (PARTITION BY pd.Id) AS adjusted_score,
    RANK() OVER (
      ORDER BY 
        SUM(CASE WHEN t.post_count > 100 THEN pd.Score ELSE 0 END) OVER (PARTITION BY pd.Id) DESC, 
        pd.link_count DESC
    ) AS popularity_rank
  FROM post_details pd
  LEFT JOIN parsed_tags pt ON pd.Id = pt.Id
  LEFT JOIN tag_stats t ON pt.tag = t.tag
  LEFT JOIN Posts p_owner ON pd.Id = p_owner.Id
  LEFT JOIN user_engagement ue ON p_owner.OwnerUserId = ue.UserId
  WHERE ue.gold_badges > 0 OR pd.high_score_comments > 0
),
final_ranking AS (
  SELECT 
    Id,
    Title,
    Score,
    link_count,
    high_score_comments,
    adjusted_score,
    total_vote_score,
    gold_badges,
    popularity_rank
  FROM enriched_posts
  WHERE popularity_rank <= 10
    AND adjusted_score IS NOT NULL
)
SELECT 
  fr.Id,
  fr.Title,
  CASE 
    WHEN fr.adjusted_score > 100 THEN 'High Impact'
    WHEN fr.adjusted_score > 50 THEN 'Medium Impact'
    ELSE 'Low Impact'
  END AS impact_level,
  fr.Score,
  fr.link_count,
  fr.high_score_comments,
  fr.adjusted_score,
  fr.total_vote_score,
  fr.gold_badges
FROM final_ranking fr
ORDER BY fr.popularity_rank;
