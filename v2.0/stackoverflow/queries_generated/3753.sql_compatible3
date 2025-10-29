WITH
    recent_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.OwnerUserId,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.Tags,
            p.AnswerCount,
            p.FavoriteCount,
            p.ClosedDate,
            p.CommunityOwnedDate
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= CAST(CAST('2024-10-01' AS date) - INTERVAL '180' DAY AS date)
    ),

    question_tags AS (
        SELECT
            q.Id,
            UNNEST(string_to_array(SUBSTR(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS tag
        FROM recent_questions q
    ),

    tag_stats AS (
        SELECT
            t.tag,
            COUNT(DISTINCT t.Id)                                           AS question_cnt,
            AVG(q.Score) FILTER (WHERE q.Score IS NOT NULL)               AS avg_score,
            SUM(q.ViewCount)                                               AS total_views,
            MAX(q.CreationDate)                                            AS latest_question_date
        FROM question_tags t
        JOIN Posts q ON q.Id = t.Id
        GROUP BY t.tag
    ),

    top_tags AS (
        SELECT
            ts.tag,
            ts.question_cnt,
            ts.avg_score,
            ts.total_views,
            ts.latest_question_date,
            ROW_NUMBER() OVER (ORDER BY ts.question_cnt DESC)              AS tag_rank,
            tg.Count                                                        AS global_tag_count,
            tg.IsModeratorOnly,
            tg.TagName
        FROM tag_stats ts
        LEFT JOIN Tags tg ON tg.TagName = ts.tag
        WHERE (tg.IsModeratorOnly = FALSE) OR (tg.IsModeratorOnly IS NULL)
    ),

    user_activity AS (
        SELECT
            u.Id                                     AS user_id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate                           AS user_since,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS up_votes_given,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS down_votes_given
        FROM Users u
        LEFT JOIN Votes v ON v.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    ),

    best_answerer_per_tag AS (
        SELECT
            tt.tag,
            a.OwnerUserId                                                   AS user_id,
            ROW_NUMBER() OVER (PARTITION BY tt.tag ORDER BY a.Score DESC)   AS rn
        FROM top_tags tt
        JOIN question_tags qt ON qt.tag = tt.tag
        JOIN Posts q ON q.Id = qt.Id
        JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
        WHERE a.Score IS NOT NULL
    )

SELECT
    tt.tag_rank,
    tt.tag,
    tt.question_cnt,
    ROUND(CAST(tt.avg_score AS numeric), 2)                  AS avg_score,
    tt.total_views,
    tt.global_tag_count,
    ua.DisplayName                                  AS top_answerer,
    ua.Reputation                                   AS top_answerer_rep,
    ua.up_votes_given,
    ua.down_votes_given,
    CASE
        WHEN tt.latest_question_date IS NOT NULL AND EXISTS (
            SELECT 1 FROM Posts p2
            WHERE p2.PostTypeId = 1
              AND p2.Tags LIKE '%' || '<' || tt.tag || '>' || '%'
              AND p2.CreationDate = tt.latest_question_date
              AND p2.ClosedDate IS NOT NULL
        ) THEN 'Closed'
        WHEN tt.latest_question_date IS NOT NULL AND EXISTS (
            SELECT 1 FROM Posts p3
            WHERE p3.PostTypeId = 1
              AND p3.Tags LIKE '%' || '<' || tt.tag || '>' || '%'
              AND p3.CreationDate = tt.latest_question_date
              AND p3.CommunityOwnedDate IS NOT NULL
        ) THEN 'CommunityOwned'
        ELSE 'Open'
    END                                              AS status,
    (SELECT COUNT(*)
     FROM Votes v
     WHERE v.PostId = (
           SELECT q2.Id
           FROM Posts q2
           WHERE q2.PostTypeId = 1
             AND q2.Tags LIKE '%' || '<' || tt.tag || '>' || '%'
           ORDER BY q2.CreationDate DESC
           LIMIT 1)
       AND v.VoteTypeId = 2)                           AS recent_question_upvotes
FROM top_tags tt
LEFT JOIN best_answerer_per_tag ba ON ba.tag = tt.tag AND ba.rn = 1
LEFT JOIN user_activity ua ON ua.user_id = ba.user_id
WHERE tt.tag_rank <= 15

UNION ALL

SELECT
    CAST(NULL AS integer) AS tag_rank,
    '---'          AS tag,
    CAST(NULL AS bigint)   AS question_cnt,
    CAST(NULL AS numeric)  AS avg_score,
    CAST(NULL AS bigint)   AS total_views,
    CAST(NULL AS bigint)   AS global_tag_count,
    CAST(NULL AS text)     AS top_answerer,
    CAST(NULL AS integer)  AS top_answerer_rep,
    CAST(NULL AS integer)  AS up_votes_given,
    CAST(NULL AS integer)  AS down_votes_given,
    CAST(NULL AS text)     AS status,
    CAST(NULL AS bigint)   AS recent_question_upvotes
FROM (SELECT 1) s

ORDER BY tag_rank NULLS LAST;