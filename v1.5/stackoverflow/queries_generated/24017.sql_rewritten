-- {"query": "24017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4425} 
WITH
    -- Count questions by user
    question_cte AS (
        SELECT OwnerUserId,
               COUNT(*) AS question_cnt,
               SUM(Score) AS question_score
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ),
    -- Count answers by user
    answer_cte AS (
        SELECT OwnerUserId,
               COUNT(*) AS answer_cnt,
               SUM(Score) AS answer_score
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ),
    -- Merge counts (FULL JOIN keeps users that have only questions or only answers)
    post_counts AS (
        SELECT
            COALESCE(q.OwnerUserId, a.OwnerUserId)                               AS OwnerUserId,
            COALESCE(q.question_cnt, 0)                                         AS question_cnt,
            COALESCE(a.answer_cnt, 0)                                           AS answer_cnt,
            COALESCE(q.question_score, 0)                                      AS question_score,
            COALESCE(a.answer_score, 0)                                         AS answer_score
        FROM question_cte q
        FULL JOIN answer_cte a USING (OwnerUserId)
    ),
    -- Total votes cast by each user
    vote_totals AS (
        SELECT
            u.Id                                            AS UserId,
            COUNT(v.Id)                                     AS total_votes,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
        FROM Users u
        LEFT JOIN Votes v ON v.UserId = u.Id
        GROUP BY u.Id
    ),
    -- Number of edits per post (window partition keeps the count per row)
    edits_per_post AS (
        SELECT
            ph.PostId,
            COUNT(*) OVER (PARTITION BY ph.PostId) AS edit_count
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (5,6)      -- edited body or tags
    ),
    -- Average edits per post for each user
    avg_edits AS (
        SELECT
            p.OwnerUserId,
            AVG(e.edit_count) AS avg_edit
        FROM Posts p
        JOIN edits_per_post e ON e.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),
    -- Concatenate distinct tags used by each user
    tags_string AS (
        SELECT
            p.OwnerUserId,
            STRING_AGG(DISTINCT t.TagName, ', ') AS tags
        FROM Posts p
        CROSS JOIN LATERAL
            UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        JOIN Tags t ON t.TagName = tag
        GROUP BY p.OwnerUserId
    ),
    -- Aggregate user details
    user_detail AS (
        SELECT
            u.Id,
            u.Reputation,
            COALESCE(pc.question_cnt,0) + COALESCE(pc.answer_cnt,0) AS total_posts,
            COALESCE(pc.question_score,0) AS total_q_score,
            COALESCE(pc.answer_score,0) AS total_a_score,
            COALESCE(vt.total_votes,0)  AS votes_cast,
            COALESCE(vt.upvotes,0)      AS votes_up,
            COALESCE(vt.downvotes,0)    AS votes_down,
            COALESCE(ts.tags,'')        AS tag_list,
            COALESCE(a.avg_edit,0)      AS avg_edit_per_post,
            -- correlated sub‑query for number of comments
            (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS comment_cnt
        FROM Users u
        LEFT JOIN post_counts pc ON pc.OwnerUserId = u.Id
        LEFT JOIN vote_totals vt ON vt.UserId = u.Id
        LEFT JOIN tags_string ts ON ts.OwnerUserId = u.Id
        LEFT JOIN avg_edits a ON a.OwnerUserId = u.Id
    )
SELECT
    Id           AS user_id,
    Reputation,
    total_posts,
    total_q_score,
    total_a_score,
    votes_cast,
    votes_up,
    votes_down,
    tag_list,
    avg_edit_per_post,
    comment_cnt,
    DENSE_RANK() OVER (ORDER BY votes_cast DESC, total_posts DESC) AS rank,
    CASE WHEN tag_list = '' THEN NULL ELSE tag_list END AS tags_norm
FROM user_detail
WHERE Reputation >= 1000
ORDER BY rank, Reputation DESC;