-- {"query": "3041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3202} 
WITH top_users AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(bc.gold, 0)   AS gold_badges,
           COALESCE(bc.silver, 0) AS silver_badges,
           COALESCE(bc.bronze, 0) AS bronze_badges,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
),

tag_stats AS (
    SELECT t.TagName,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_q_score,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_a_score
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT *
        FROM Posts p
        WHERE p.Tags IS NOT NULL
          AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    ) p ON TRUE
    GROUP BY t.TagName
),

recent_activity AS (
    SELECT p.Id         AS post_id,
           p.Title,
           p.CreationDate,
           p.Score,
           u.DisplayName AS owner_name,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
           p.PostTypeId
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),

answer_scores AS (
    SELECT q.Id                     AS question_id,
           q.Title,
           q.Score                  AS question_score,
           (SELECT AVG(a.Score)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS avg_answer_score,
           (SELECT COUNT(*)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2 AND a.Score > 0) AS positive_answer_cnt
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),

high_score_union AS (
    SELECT p.Id,
           p.Title,
           p.CreationDate,
           p.Score,
           p.PostTypeId,
           'Question' AS type_label
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 50

    UNION ALL

    SELECT a.Id,
           a.Title,
           a.CreationDate,
           a.Score,
           a.PostTypeId,
           'Answer'   AS type_label
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.Score > 100
)

SELECT
    ra.post_id,
    ra.Title,
    ra.CreationDate,
    ra.Score,
    ra.owner_name,
    ts.TagName,
    COALESCE(ts.avg_q_score, 0)          AS avg_question_score_for_tag,
    COALESCE(asrc.avg_answer_score, 0)   AS avg_answer_score_for_question,
    CASE WHEN ra.rn = 1 THEN 'TopRecent' ELSE NULL END AS flag
FROM recent_activity ra
LEFT JOIN tag_stats ts
       ON ts.TagName = (
           SELECT TRIM(BOTH '>' FROM SPLIT_PART(SPLIT_PART(ra.Title, '<', 2), '>', 1))
       )
LEFT JOIN answer_scores asrc
       ON asrc.question_id = ra.post_id
WHERE ra.rn <= 5

UNION ALL

SELECT
    hs.Id,
    hs.Title,
    hs.CreationDate,
    hs.Score,
    u.DisplayName,
    NULL AS TagName,
    NULL AS avg_question_score_for_tag,
    NULL AS avg_answer_score_for_question,
    hs.type_label AS flag
FROM high_score_union hs
LEFT JOIN Users u
       ON u.Id = (SELECT OwnerUserId FROM Posts p WHERE p.Id = hs.Id)

ORDER BY CreationDate DESC
LIMIT 100;