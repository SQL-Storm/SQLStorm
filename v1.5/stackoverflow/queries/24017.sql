WITH
    question_cte AS (
        SELECT OwnerUserId,
               COUNT(*) AS question_cnt,
               SUM(Score) AS question_score
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ),
    answer_cte AS (
        SELECT OwnerUserId,
               COUNT(*) AS answer_cnt,
               SUM(Score) AS answer_score
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ),
    post_counts AS (
        SELECT
            COALESCE(q.OwnerUserId, a.OwnerUserId)                               AS OwnerUserId,
            COALESCE(q.question_cnt, 0)                                         AS question_cnt,
            COALESCE(a.answer_cnt, 0)                                           AS answer_cnt,
            COALESCE(q.question_score, 0)                                      AS question_score,
            COALESCE(a.answer_score, 0)                                         AS answer_score
        FROM question_cte q
        FULL OUTER JOIN answer_cte a ON q.OwnerUserId = a.OwnerUserId
    ),
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
    edits_per_post AS (
        SELECT
            ph.PostId,
            COUNT(*) OVER (PARTITION BY ph.PostId) AS edit_count
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (5,6)
    ),
    avg_edits AS (
        SELECT
            p.OwnerUserId,
            AVG(e.edit_count) AS avg_edit
        FROM Posts p
        JOIN edits_per_post e ON e.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),
    tags_string AS (
        SELECT
            p.OwnerUserId,
            STRING_AGG(DISTINCT t.TagName, ', ') AS tags
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT tag FROM (
                SELECT UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
            ) AS sub
        ) AS tag_alias
        JOIN Tags t ON t.TagName = tag_alias.tag
        GROUP BY p.OwnerUserId
    ),
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