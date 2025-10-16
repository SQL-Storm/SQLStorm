-- {"query": "210.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3887} 
WITH
  base_posts AS (
    SELECT p.*,
      COALESCE(p.Tags,'') AS TagsClean,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST) AS rn_owner_recent
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
      AND p.CreationDate >= now() - interval '5 years'
  ),
  votes_summary AS (
    SELECT v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS vote_balance,
      SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
      COUNT(*) AS votes_total,
      MAX(v.CreationDate) AS last_vote_date
    FROM Votes v
    GROUP BY v.PostId
  ),
  comments_summary AS (
    SELECT c.PostId,
      COUNT(*) AS comments_count,
      MAX(c.CreationDate) AS last_comment_date,
      MIN(c.CreationDate) AS first_comment_date,
      SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS anonymous_comments
    FROM Comments c
    GROUP BY c.PostId
  ),
  tags AS (
    SELECT p.Id AS PostId,
           trim(t) AS tag
    FROM Posts p
    JOIN LATERAL unnest(
      string_to_array(
        substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,'')) - 2, 0)
      ), '><')
    ) AS t ON true
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
  ),
  tag_stats AS (
    SELECT t.tag,
      COUNT(DISTINCT t.PostId) AS questions_with_tag,
      COUNT(DISTINCT p.OwnerUserId) FILTER (WHERE p.OwnerUserId IS NOT NULL) AS distinct_askers,
      AVG(p.Score) AS avg_question_score
    FROM tags t
    JOIN Posts p ON p.Id = t.PostId
    GROUP BY t.tag
  ),
  exploded AS (
    SELECT bp.Id, bp.PostTypeId, bp.Title, bp.OwnerUserId, bp.CreationDate, bp.LastActivityDate, bp.Score, bp.ViewCount,
      COALESCE(vs.vote_balance,0) AS vote_balance,
      COALESCE(vs.votes_total,0) AS votes_total,
      COALESCE(cs.comments_count,0) AS comments_count,
      bp.TagsClean
    FROM base_posts bp
    LEFT JOIN votes_summary vs ON vs.PostId = bp.Id
    LEFT JOIN comments_summary cs ON cs.PostId = bp.Id
  ),
  ranked_by_tag AS (
    SELECT e.*,
      t.tag,
      ROW_NUMBER() OVER (PARTITION BY t.tag ORDER BY e.Score DESC NULLS LAST, e.vote_balance DESC NULLS LAST, e.ViewCount DESC NULLS LAST) AS tag_rank,
      PERCENT_RANK() OVER (PARTITION BY t.tag ORDER BY e.Score DESC NULLS LAST) AS score_percentile
    FROM exploded e
    JOIN tags t ON t.PostId = e.Id
    WHERE e.PostTypeId = 1
  ),
  top_candidates AS (
    SELECT DISTINCT ON (r.tag) r.tag, r.Id AS PostId, r.Title, r.Score, r.vote_balance, r.comments_count, r.tag_rank, r.score_percentile
    FROM ranked_by_tag r
    ORDER BY r.tag, r.score_percentile DESC NULLS LAST, r.Score DESC NULLS LAST, r.vote_balance DESC NULLS LAST
  ),
  merged_set AS (
    SELECT tag, PostId, Title, Score, vote_balance, comments_count, tag_rank FROM top_candidates
    UNION ALL
    SELECT t.tag, p.Id, p.Title, p.Score, COALESCE(vs.vote_balance,0), COALESCE(cs.comments_count,0), NULL
    FROM tags t
    JOIN Posts p ON p.Id = t.PostId
    LEFT JOIN votes_summary vs ON vs.PostId = p.Id
    LEFT JOIN comments_summary cs ON cs.PostId = p.Id
    WHERE p.CreationDate > now() - interval '30 days'
  ),
  filtered AS (
    SELECT m.*,
      CASE WHEN Score IS NULL THEN -999 ELSE Score END AS Score_no_null,
      COALESCE(vote_balance,0) + COALESCE(comments_count,0) AS engagement_score,
      SUBSTRING(COALESCE(Title,''),1,140) || CASE WHEN LENGTH(COALESCE(Title,''))>140 THEN '...' ELSE '' END AS title_snippet
    FROM merged_set m
    WHERE COALESCE(Score,0) >= (SELECT COALESCE(MIN(Score),0) FROM Posts WHERE PostTypeId = 1) - 1000
  ),
  final_candidates AS (
    SELECT f.*,
      ROW_NUMBER() OVER (PARTITION BY f.tag ORDER BY f.engagement_score DESC, f.Score_no_null DESC) AS final_rank,
      NTILE(4) OVER (ORDER BY f.engagement_score DESC) AS quartile
    FROM filtered f
  )
SELECT fc.tag,
       fc.PostId,
       fc.title_snippet AS title,
       fc.Score,
       fc.vote_balance,
       fc.comments_count,
       fc.engagement_score,
       fc.final_rank,
       fc.quartile,
       ts.questions_with_tag,
       ts.avg_question_score,
       u.DisplayName AS top_asker,
       COALESCE(u.Reputation,0) AS asker_reputation,
       CASE WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN '(unknown)' ELSE u.Location END AS asker_location,
       CASE WHEN fc.Score > (ts.avg_question_score) THEN 'above_avg' WHEN fc.Score = ts.avg_question_score THEN 'at_avg' ELSE 'below_avg' END AS score_vs_tag_avg
FROM final_candidates fc
LEFT JOIN tag_stats ts ON ts.tag = fc.tag
LEFT JOIN LATERAL (
  SELECT u2.DisplayName, u2.Reputation, u2.Location
  FROM Posts p2
  JOIN Users u2 ON u2.Id = p2.OwnerUserId
  WHERE p2.Id = fc.PostId AND p2.OwnerUserId IS NOT NULL
  ORDER BY u2.Reputation DESC NULLS LAST
  LIMIT 1
) u ON true
WHERE fc.final_rank <= 3
ORDER BY fc.tag, fc.final_rank, fc.engagement_score DESC;