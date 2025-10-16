-- {"query": "205.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4329} 
WITH tag_expanded AS (
  SELECT p.id AS postid,
         lower(trim(unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')))) AS tag
  FROM posts p
  WHERE p.tags IS NOT NULL AND p.posttypeid = 1
),
tag_popularity AS (
  SELECT te.tag,
         COUNT(*)::int AS question_count,
         SUM(COALESCE(p.score,0)) AS total_score,
         AVG(COALESCE(p.viewcount,0)) AS avg_views,
         MAX(p.score) AS max_score
  FROM tag_expanded te
  JOIN posts p ON p.id = te.postid
  GROUP BY te.tag
),
user_activity AS (
  SELECT u.id AS user_id,
         u.displayname,
         COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS q_count,
         COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS a_count,
         SUM(COALESCE(p.score,0)) AS post_score,
         COUNT(v.id) FILTER (WHERE v.votetypeid = 2) AS upvotes_received
  FROM users u
  LEFT JOIN posts p ON p.owneruserid = u.id
  LEFT JOIN votes v ON v.postid = p.id
  GROUP BY u.id, u.displayname
),
badge_weighted AS (
  SELECT b.userid,
         SUM(CASE WHEN b.class = 1 THEN 5 WHEN b.class = 2 THEN 3 ELSE 1 END) AS badge_points,
         COUNT(*) AS badge_count
  FROM badges b
  GROUP BY b.userid
),
top_posts_per_tag AS (
  SELECT te.tag, p.id AS postid, p.title, p.score,
         ROW_NUMBER() OVER (PARTITION BY te.tag ORDER BY p.score DESC NULLS LAST, p.viewcount DESC NULLS LAST) AS rn
  FROM tag_expanded te
  JOIN posts p ON p.id = te.postid
  WHERE p.creationdate > now() - interval '2 years'
),
recent_comments AS (
  SELECT c.postid, COUNT(*) AS recent_comment_count
  FROM comments c
  WHERE c.creationdate > now() - interval '90 days'
  GROUP BY c.postid
),
answer_stats AS (
  SELECT a.parentid AS questionid,
         COUNT(*) AS answers_total,
         SUM(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS accepted_exists,
         AVG(a.score) AS avg_answer_score,
         MAX(a.creationdate) FILTER (WHERE a.score IS NOT NULL) AS newest_answer
  FROM posts a
  JOIN posts q ON q.id = a.parentid
  WHERE a.posttypeid = 2
  GROUP BY a.parentid, q.acceptedanswerid
),
duplicates AS (
  SELECT pl.postid, pl.relatedpostid, pl.creationdate
  FROM postlinks pl
  WHERE pl.linktypeid = 3
),
scored_posts AS (
  SELECT p.*,
         COALESCE(up.up_count,0) AS upvotes_last30,
         COALESCE(rec.recent_comment_count,0) AS recent_comments,
         COALESCE(a.answers_total,0) AS answers_total,
         COALESCE(a.avg_answer_score,0)::numeric(10,2) AS avg_answer_score,
         COALESCE(bw.badge_points,0) AS owner_badge_points,
         COALESCE(ua.post_score,0) AS owner_post_score,
         COALESCE(ua.q_count,0) AS owner_q_count,
         CASE WHEN p.acceptedanswerid IS NOT NULL THEN 1 ELSE 0 END AS has_accepted
  FROM posts p
  LEFT JOIN (
     SELECT v.postid, COUNT(*) FILTER (WHERE v.creationdate > now() - interval '30 days' AND v.votetypeid = 2) AS up_count
     FROM votes v
     GROUP BY v.postid
  ) up ON up.postid = p.id
  LEFT JOIN recent_comments rec ON rec.postid = p.id
  LEFT JOIN answer_stats a ON a.questionid = p.id
  LEFT JOIN users u ON u.id = p.owneruserid
  LEFT JOIN badge_weighted bw ON bw.userid = u.id
  LEFT JOIN user_activity ua ON ua.user_id = u.id
),
ranked AS (
  SELECT sp.*,
         DENSE_RANK() OVER (PARTITION BY COALESCE(sp.owneruserid,-1) ORDER BY sp.score DESC NULLS LAST) AS owner_rank_by_score,
         RANK() OVER (ORDER BY sp.score DESC NULLS LAST, sp.viewcount DESC NULLS LAST) AS global_rank,
         ROW_NUMBER() OVER (PARTITION BY COALESCE(sp.acceptedanswerid, -sp.id) ORDER BY sp.lastactivitydate DESC NULLS LAST) AS per_answer_rownum
  FROM scored_posts sp
),
complex_query AS (
  SELECT
    r.id,
    r.title,
    COALESCE(u.displayname, 'Community') AS owner,
    COALESCE(r.owner_badge_points,0) + COALESCE(r.owner_post_score,0) / NULLIF(GREATEST(r.owner_q_count,1),0) AS owner_influence,
    r.score,
    r.viewcount,
    r.answers_total,
    r.avg_answer_score,
    r.upvotes_last30,
    r.recent_comments,
    r.has_accepted,
    CASE
      WHEN r.score >= 100 THEN 'HighScore'
      WHEN r.score >= 10 THEN 'MediumScore'
      WHEN r.score IS NULL THEN 'Unknown'
      ELSE 'LowScore'
    END AS score_bucket,
    (SELECT COUNT(*) FROM comments c WHERE c.postid = r.id AND c.text ILIKE '%thanks%') AS thanks_count,
    (SELECT COUNT(DISTINCT v.userid) FROM votes v WHERE v.postid = r.id AND v.votetypeid IN (2,3)) AS distinct_voters,
    (SELECT string_agg(distinct te.tag, ',' ORDER BY tp.question_count DESC NULLS LAST, te.tag)
       FROM tag_expanded te
       LEFT JOIN tag_popularity tp ON tp.tag = te.tag
       WHERE te.postid = r.id) AS tags_list,
    (SELECT COUNT(*) FROM duplicates d WHERE d.postid = r.id OR d.relatedpostid = r.id) AS duplicate_link_count,
    r.global_rank,
    r.owneruserid,
    r.creationdate,
    r.lastactivitydate
  FROM ranked r
  LEFT JOIN users u ON u.id = r.owneruserid
  WHERE (r.creationdate > now() - interval '5 years' OR r.lastactivitydate > now() - interval '1 year')
    AND (r.score > COALESCE((SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score) FROM posts),0) - 5)
)
SELECT cq.*,
       tp.tag AS top_tag,
       tp.postid AS top_tag_postid,
       CASE WHEN d2.postid IS NOT NULL THEN TRUE ELSE FALSE END AS is_duplicate
FROM complex_query cq
LEFT JOIN LATERAL (
  SELECT te.tag, te.postid
  FROM tag_expanded te
  LEFT JOIN tag_popularity tp2 ON tp2.tag = te.tag
  WHERE te.postid = cq.id
  ORDER BY tp2.question_count DESC NULLS LAST, te.tag
  LIMIT 1
) tp ON true
LEFT JOIN duplicates d2 ON d2.postid = cq.id OR d2.relatedpostid = cq.id
WHERE (cq.owner_influence > 0 OR cq.upvotes_last30 > 0 OR cq.recent_comments > 0)
ORDER BY cq.global_rank NULLS LAST
LIMIT 200;