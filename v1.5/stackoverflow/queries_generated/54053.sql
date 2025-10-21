-- {"query": "54053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 3675} 
WITH
    question_posts AS (
        SELECT id,
               title,
               score,
               viewcount,
               creationdate,
               tags,
               owneruserid
        FROM posts
        WHERE posttypeid = 1
    ),
    tag_explode AS (
        SELECT qp.id AS postid,
               regexp_replace(rgt.tag, '^<|>$', '') AS tag
        FROM question_posts qp
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(qp.tags, '><') AS tag
        ) rgt
        WHERE qp.tags IS NOT NULL
    ),
    vote_counts AS (
        SELECT v.postid,
               SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
               SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes
        FROM votes v
        WHERE v.postid IN (SELECT id FROM question_posts)
        GROUP BY v.postid
    ),
    comment_counts AS (
        SELECT c.postid,
               COUNT(*) AS comment_count
        FROM comments c
        GROUP BY c.postid
    ),
    tag_stats AS (
        SELECT te.tag,
               COUNT(*) AS question_count,
               AVG(qp.score) AS avg_score,
               AVG(viewcount) AS avg_views,
               STDDEV_POP(viewcount) AS stddev_views,
               AVG((COALESCE(vc.upvotes,0) - COALESCE(vc.downvotes,0)))::numeric AS avg_net_votes,
               AVG(cc.comment_count) AS avg_comment_count
        FROM tag_explode te
        JOIN question_posts qp ON qp.id = te.postid
        LEFT JOIN vote_counts vc ON vc.postid = qp.id
        LEFT JOIN comment_counts cc ON cc.postid = qp.id
        GROUP BY te.tag
        HAVING COUNT(*) > 500
    ),
    posts_rank AS (
        SELECT id,
               score,
               viewcount,
               RANK() OVER (ORDER BY score DESC, viewcount DESC) AS rank_rank
        FROM question_posts
    ),
    tag_refine AS (
        SELECT ts.*,
               DENSE_RANK() OVER (ORDER BY ts.avg_score DESC) AS tag_rank,
               PERCENT_RANK() OVER (ORDER BY ts.avg_score) AS tag_rank_pct
        FROM tag_stats ts
    )
SELECT tr.tag,
       tr.question_count,
       tr.avg_score,
       tr.total_score,
       tr.avg_views,
       tr.stddev_views,
       tr.avg_net_votes,
       tr.avg_comment_count,
       tr.tag_rank,
       tr.tag_rank_pct,
       COUNT(DISTINCT CASE WHEN pr.rank_rank <= 1000 THEN pr.id END) AS top_ranked_questions
FROM tag_refine tr
LEFT JOIN posts_rank pr ON pr.rank_rank <= 1000
GROUP BY tr.tag,
         tr.question_count,
         tr.avg_score,
         tr.total_score,
         tr.avg_views,
         tr.stddev_views,
         tr.avg_net_votes,
         tr.avg_comment_count,
         tr.tag_rank,
         tr.tag_rank_pct
ORDER BY tr.tag_rank
LIMIT 20;