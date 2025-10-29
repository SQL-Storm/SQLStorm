-- {"query": "3422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1537}
WITH
top_users AS (
    SELECT
        u.Id                                            AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(MAX(p.CreationDate), u.CreationDate)    AS last_post_date,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(MAX(p.CreationDate), u.CreationDate) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 5
),

recent_questions AS (
    SELECT
        q.Id                                 AS q_id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.Tags,
        ARRAY_AGG(tag_trim.t ORDER BY tag_trim.t) AS tag_list
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS t
        FROM (
            -- split tags stored like '<tag1><tag2>' into rows
            -- standard SQL: replace the surrounding <> then split on '><'
            SELECT value
            FROM UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR CHAR_LENGTH(q.Tags) - 2), '><')) AS value
        ) AS split_vals
    ) AS tag_trim
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.CreationDate, q.Tags
),

user_badge_agg AS (
    SELECT
        b.UserId                                          AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)      AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)      AS bronze_cnt,
        STRING_AGG(DISTINCT b.Name, ';')                  AS badge_names
    FROM Badges b
    WHERE b.Class IN (1,2,3)
    GROUP BY b.UserId
),

post_vote_summary AS (
    SELECT
        v.PostId                                      AS post_id,
        SUM(CASE WHEN vt.Id = 2 THEN 1
                 WHEN vt.Id = 3 THEN -1
                 ELSE 0 END)                         AS net_score,
        SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END)   AS favorites,
        MAX(v.CreationDate)                          AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),

linked_or_duplicate AS (
    SELECT
        pl.PostId        AS src_id,
        pl.RelatedPostId AS tgt_id,
        lt.Name          AS link_type
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Id IN (1,3)
),

latest_edit_comment AS (
    SELECT
        ph.PostId,
        ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate)
            FROM PostHistory ph2
            WHERE ph2.PostId = ph.PostId
              AND ph2.PostHistoryTypeId IN (4,5,6)
      )
),

question_detail AS (
    SELECT
        q.q_id,
        q.Title,
        q.Score                AS question_score,
        q.ViewCount,
        q.CreationDate,
        q.tag_list,
        COALESCE(vs.net_score,0)   AS net_vote_score,
        COALESCE(vs.favorites,0)   AS favorite_cnt,
        le.Comment                 AS latest_edit_comment,
        CARDINALITY(q.tag_list)    AS tag_count
    FROM recent_questions q
    LEFT JOIN post_vote_summary vs ON vs.post_id = q.q_id
    LEFT JOIN latest_edit_comment le ON le.PostId = q.q_id
),

answer_rank AS (
    SELECT
        a.ParentId                           AS question_id,
        a.Id                                 AS answer_id,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, a.Id, a.Score, a.CreationDate
),

high_score_questions AS (
    SELECT
        qd.q_id               AS entity_id,
        qd.Title              AS description,
        qd.question_score     AS metric,
        'Question'            AS entity_type,
        qd.tag_count          AS extra_metric
    FROM question_detail qd
    WHERE qd.question_score >= 10
      AND qd.tag_count BETWEEN 1 AND 5
),

gold_badge_users AS (
    SELECT
        ub.user_id           AS entity_id,
        u.DisplayName        AS description,
        ub.gold_cnt          AS metric,
        'User'               AS entity_type,
        ub.silver_cnt        AS extra_metric
    FROM user_badge_agg ub
    JOIN Users u ON u.Id = ub.user_id
    WHERE ub.gold_cnt >= 3
)

SELECT entity_id, description, metric, entity_type, extra_metric
FROM high_score_questions
UNION ALL
SELECT entity_id, description, metric, entity_type, extra_metric
FROM gold_badge_users
ORDER BY metric DESC, extra_metric DESC
LIMIT 200;