-- {"query": "25033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2310} 

WITH
    question_stats AS (
        SELECT
            q.Id                                   AS question_id,
            q.Title,
            q.CreationDate,
            q.Score                                AS question_score,
            q.ViewCount,
            q.Tags,
            COALESCE(q.AnswerCount, 0)             AS answer_count,
            COUNT(a.Id)                            AS total_answers,
            AVG(a.Score)                           AS avg_answer_score,
            MAX(a.CreationDate)                    AS latest_answer_date,
            STRING_AGG(DISTINCT CAST(a.OwnerUserId AS VARCHAR), ',') AS answerer_ids,
            MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Text END) AS latest_title_edit,
            COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 5)          AS edit_body_cnt,
            ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY ph.CreationDate DESC) AS rn_hist
        FROM Posts q
        LEFT JOIN Posts a
               ON a.ParentId = q.Id AND a.PostTypeId = 2
        LEFT JOIN PostHistory ph
               ON ph.PostId = q.Id
              AND ph.PostHistoryTypeId IN (4,5)
        WHERE q.PostTypeId = 1                     -- only questions
        GROUP BY q.Id, q.Title, q.CreationDate, q.Score,
                 q.ViewCount, q.Tags, q.AnswerCount
    ),
    user_activity AS (
        SELECT
            u.Id                                   AS user_id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.CreationDate, TIMESTAMP '1970-01-01') AS user_since,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_asked,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_given,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_given,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_given,
            COUNT(b.Id)                              AS badges_earned,
            MAX(b.Class)                             AS highest_badge_class
        FROM Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v   ON v.UserId = u.Id
        LEFT JOIN Badges b  ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    ),
    latest_comment AS (
        SELECT
            c.PostId,
            c.Text            AS comment_text,
            c.CreationDate    AS comment_date,
            ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
        FROM Comments c
    )
SELECT
    qs.question_id,
    qs.Title,
    qs.CreationDate,
    qs.question_score,
    qs.ViewCount,
    qs.answer_count,
    qs.total_answers,
    qs.avg_answer_score,
    COALESCE(qs.latest_answer_date, qs.CreationDate)   AS last_activity,
    CASE
        WHEN qs.Tags IS NULL THEN 'untagged'
        ELSE REPLACE(SUBSTRING(qs.Tags FROM 2 FOR LENGTH(qs.Tags)-2), '><', ',')
    END                                              AS tag_list,
    ua.user_id,
    ua.DisplayName,
    ua.Reputation,
    ua.questions_asked,
    ua.answers_given,
    ua.upvotes_given,
    ua.downvotes_given,
    ua.badges_earned,
    ua.highest_badge_class,
    lc.comment_text,
    lc.comment_date,
    qs.edit_body_cnt,
    qs.latest_title_edit
FROM question_stats qs
LEFT JOIN user_activity ua
       ON ua.user_id = (SELECT OwnerUserId FROM Posts WHERE Id = qs.question_id)
LEFT JOIN latest_comment lc
       ON lc.PostId = qs.question_id AND lc.rn = 1
WHERE (qs.question_score + COALESCE(qs.avg_answer_score,0)) > 0
  AND (ua.Reputation IS NULL OR ua.Reputation > 100)

UNION ALL

SELECT
    p.Id                                      AS question_id,
    p.Title,
    p.CreationDate,
    p.Score                                   AS question_score,
    p.ViewCount,
    p.AnswerCount,
    NULL                                      AS total_answers,
    NULL                                      AS avg_answer_score,
    p.LastActivityDate                        AS last_activity,
    NULL                                      AS tag_list,
    NULL                                      AS user_id,
    NULL                                      AS DisplayName,
    NULL                                      AS Reputation,
    NULL                                      AS questions_asked,
    NULL                                      AS answers_given,
    NULL                                      AS upvotes_given,
    NULL                                      AS downvotes_given,
    NULL                                      AS badges_earned,
    NULL                                      AS highest_badge_class,
    NULL                                      AS comment_text,
    NULL                                      AS comment_date,
    NULL                                      AS edit_body_cnt,
    NULL                                      AS latest_title_edit
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'

ORDER BY question_id DESC
LIMIT 100;
