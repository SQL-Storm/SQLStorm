-- {"query": "39068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1606} 

WITH
-- Extract individual tags from question posts
tag_list AS (
    SELECT
        p.id                     AS question_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><')) AS tag
    FROM posts p
    WHERE p.posttypeid = 1
),
-- Compute tag usage counts
tag_usage AS (
    SELECT
        tag,
        COUNT(*) AS usage_count
    FROM tag_list
    GROUP BY tag
),
-- Compute per-question vote breakdown
vote_breakdown AS (
    SELECT
        p.id,
        p.title,
        COUNT(CASE WHEN v.votetypeid = 2 THEN 1 END) AS upvotes,
        COUNT(CASE WHEN v.votetypeid = 3 THEN 1 END) AS downvotes,
        COUNT(CASE WHEN v.votetypeid = 5 THEN 1 END) AS favorites
    FROM posts p
    LEFT JOIN votes v ON v.postid = p.id
    GROUP BY p.id, p.title
),
-- Compute comment counts for questions
comment_counts AS (
    SELECT
        c.postid AS question_id,
        COUNT(*) AS comment_count
    FROM comments c
    GROUP BY c.postid
),
-- Rank answers by score for each question
top_answers AS (
    SELECT
        a.parentid AS question_id,
        a.id       AS answer_id,
        a.score,
        ROW_NUMBER() OVER (PARTITION BY a.parentid ORDER BY a.score DESC, a.creationdate) AS answer_rank
    FROM posts a
    WHERE a.posttypeid = 2
),
-- Gather latest edit times and total edit counts per post
edit_history AS (
    SELECT
        ph.postid,
        MAX(ph.creationdate) AS last_edit,
        COUNT(*)            AS total_edits
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (4,5,6,7,8,9)
    GROUP BY ph.postid
),
-- Select top 10 tags by usage
top_10_tags AS (
    SELECT tag, usage_count
    FROM tag_usage
    ORDER BY usage_count DESC
    LIMIT 10
)
SELECT
    t10.tag                       AS top_tag,
    t10.usage_count               AS tag_usage,
    vb.title                      AS question_title,
    vb.upvotes,
    vb.downvotes,
    vb.favorites,
    coalesce(cc.comment_count, 0) AS comments,
    ta.answer_id                  AS top_answer_id,
    ta.score                      AS top_answer_score,
    u.displayname                 AS question_author,
    u.reputation                  AS author_reputation,
    eh.last_edit,
    eh.total_edits
FROM top_10_tags t10
JOIN tag_list tl
  ON tl.tag = t10.tag
JOIN vote_breakdown vb
  ON vb.id = tl.question_id
LEFT JOIN comment_counts cc
  ON cc.question_id = tl.question_id
LEFT JOIN top_answers ta
  ON ta.question_id = tl.question_id
 AND ta.answer_rank = 1
LEFT JOIN users u
  ON u.id = (SELECT owneruserid FROM posts WHERE id = tl.question_id)
LEFT JOIN edit_history eh
  ON eh.postid = tl.question_id
ORDER BY t10.usage_count DESC,
         vb.upvotes DESC,
         ta.score DESC;
