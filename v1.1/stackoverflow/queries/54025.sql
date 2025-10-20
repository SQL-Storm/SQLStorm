WITH
    question_stat AS (
        SELECT
            p.Id                           AS q_id,
            p.Tags                         AS tags,
            p.AnswerCount                  AS ans_cnt,
            p.Score                        AS q_score,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upv_cnt,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downv_cnt,
            MIN(ph.CreationDate)           AS first_edit,
            MAX(ph.CreationDate)           AS last_edit,
            COUNT(c.Id)                    AS comment_cnt
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (5,7)
        LEFT JOIN Comments c ON c.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id, p.Tags, p.AnswerCount, p.Score
    ),
    user_stats AS (
        SELECT
            u.Id              AS u_id,
            u.DisplayName     AS u_name,
            u.Reputation      AS rep,
            COUNT(DISTINCT p.Id)                                   AS posts_auth,
            SUM(p.Score)                                           AS sum_post_score,
            SUM(q.ans_cnt)                                         AS total_ans,
            SUM(q.upv_cnt)                                         AS total_upv,
            SUM(q.downv_cnt)                                       AS total_downv,
            COUNT(DISTINCT c.Id) FILTER (WHERE c.UserId = u.Id)    AS comments_made,
            COUNT(DISTINCT v.Id) FILTER (WHERE v.UserId = u.Id)    AS votes_cast,
            COUNT(DISTINCT ph.Id) FILTER (WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10) AS close_votes,
            COUNT(b.Id)                                            AS badges_count,
            AVG(b.Class)                                           AS avg_badge_cls
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN question_stat q ON q.q_id = p.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Votes v ON v.UserId = u.Id
        LEFT JOIN PostHistory ph ON ph.UserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    tag_stats AS (
        SELECT
            t.TagName          AS tag_name,
            COUNT(q.q_id)      AS num_ques,
            AVG(q.ans_cnt)     AS avg_ans,
            SUM(q.upv_cnt)     AS total_upv,
            SUM(q.downv_cnt)   AS total_downv,
            SUM(q.q_score)     AS total_score,
            MIN(q.first_edit)  AS earliest_edit,
            MAX(q.last_edit)   AS latest_edit
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
        JOIN question_stat q ON q.q_id = p.Id
        GROUP BY t.TagName
    ),
    composite_user AS (
        SELECT
            uf.u_id,
            uf.u_name,
            uf.rep,
            uf.posts_auth,
            uf.sum_post_score,
            uf.total_ans,
            uf.total_upv,
            uf.total_downv,
            uf.comments_made,
            uf.votes_cast,
            uf.close_votes,
            uf.badges_count,
            uf.avg_badge_cls,
            (
                COALESCE(uf.sum_post_score,0)
                + COALESCE(uf.posts_auth,0) * 10
                + COALESCE(uf.total_ans,0) * 5
                + COALESCE(uf.total_upv,0) * 2
                + COALESCE(uf.total_downv,0) * -1
                + COALESCE(uf.close_votes,0) * 15
                + COALESCE(uf.avg_badge_cls,0) * 20
            ) AS comp_score
        FROM user_stats uf
    )
SELECT
    cu.u_id                   AS user_id,
    cu.u_name                 AS display_name,
    cu.rep                    AS reputation,
    cu.posts_auth             AS posts_authoring,
    cu.sum_post_score         AS total_post_score,
    cu.total_ans              AS total_answers,
    cu.total_upv              AS upvotes_given,
    cu.total_downv            AS downvotes_given,
    cu.comments_made          AS comments_made,
    cu.votes_cast             AS votes_cast,
    cu.close_votes            AS close_votes_cast,
    cu.badges_count           AS badges_earned,
    cu.avg_badge_cls          AS avg_badge_class,
    cu.comp_score             AS composite_score,
    ts.num_ques               AS tag_questions,
    ts.avg_ans                AS tag_avg_answers,
    ts.total_score            AS tag_total_score
FROM composite_user cu
LEFT JOIN (
    SELECT ts.*
    FROM tag_stats ts
) ts ON EXISTS (
    SELECT 1
    FROM (
      -- split display name on whitespace into rows in a dialect-neutral way
      SELECT trim(value) AS tag
      FROM (
        SELECT
          CASE
            WHEN cu.u_name IS NULL THEN NULL
            ELSE regexp_replace(replace(cu.u_name, E'\r\n', ' '), E'\\s+', ' ', 'g')
          END AS normalized_name
      ) n
      CROSS JOIN LATERAL (
        SELECT value
        FROM (SELECT split_part(n.normalized_name, ' ', 1) AS value) s
        WHERE n.normalized_name IS NOT NULL
        UNION ALL
        SELECT value FROM (VALUES (split_part(n.normalized_name, ' ', 2))) v(value) WHERE split_part(n.normalized_name, ' ', 2) <> ''
        UNION ALL
        SELECT value FROM (VALUES (split_part(n.normalized_name, ' ', 3))) v(value) WHERE split_part(n.normalized_name, ' ', 3) <> ''
        UNION ALL
        SELECT value FROM (VALUES (split_part(n.normalized_name, ' ', 4))) v(value) WHERE split_part(n.normalized_name, ' ', 4) <> ''
        UNION ALL
        SELECT value FROM (VALUES (split_part(n.normalized_name, ' ', 5))) v(value) WHERE split_part(n.normalized_name, ' ', 5) <> ''
      ) parts
    ) part
    WHERE part.tag = ts.tag_name
)
ORDER BY cu.comp_score DESC
LIMIT 100;