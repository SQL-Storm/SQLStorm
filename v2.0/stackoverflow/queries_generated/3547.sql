-- {"query": "3547.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2538} 

/*  Performance‑benchmarking query using many advanced features  */
WITH
/* --------------------------------------------------------------
   1. Aggregate basic user activity (questions, answers, scores)
   -------------------------------------------------------------- */
user_stats AS (
    SELECT
        u.Id                               AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(pq.Id)                        AS question_cnt,
        COUNT(pa.Id)                        AS answer_cnt,
        COALESCE(SUM(pq.Score),0)           AS question_score_sum,
        COALESCE(SUM(pa.Score),0)           AS answer_score_sum,
        MAX(pq.LastActivityDate)            AS last_question_activity,
        MAX(pa.LastActivityDate)            AS last_answer_activity
    FROM Users u
    LEFT JOIN Posts pq
           ON pq.OwnerUserId = u.Id AND pq.PostTypeId = 1   -- questions
    LEFT JOIN Posts pa
           ON pa.OwnerUserId = u.Id AND pa.PostTypeId = 2   -- answers
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* --------------------------------------------------------------
   2. Count badges per user, separating gold / silver / bronze
   -------------------------------------------------------------- */
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),

/* --------------------------------------------------------------
   3. Determine each user's most used tag across their questions
   -------------------------------------------------------------- */
top_tag_per_user AS (
    SELECT
        uq.OwnerUserId                AS user_id,
        t.TagName,
        t.Count                       AS tag_use_count,
        ROW_NUMBER() OVER (PARTITION BY uq.OwnerUserId
                           ORDER BY t.Count DESC) AS rn
    FROM (
        SELECT
            p.OwnerUserId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '><' FROM p.Tags), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1               -- only questions
          AND p.Tags IS NOT NULL
    ) uq
    JOIN Tags t
      ON t.TagName = uq.tag
),

/* --------------------------------------------------------------
   4. Latest vote (up/down) per post – using a window function
   -------------------------------------------------------------- */
latest_votes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId
                           ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)               -- up‑vote / down‑vote
),

/* --------------------------------------------------------------
   5. Summarise up‑ and down‑votes per post
   -------------------------------------------------------------- */
post_vote_agg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
    GROUP BY v.PostId
),

/* --------------------------------------------------------------
   6. Merge everything together, adding windowed averages and
      handling NULL logic everywhere
   -------------------------------------------------------------- */
merged AS (
    SELECT
        us.user_id,
        us.DisplayName,
        us.Reputation,
        us.question_cnt,
        us.answer_cnt,
        us.question_score_sum,
        us.answer_score_sum,
        GREATEST(us.last_question_activity, us.last_answer_activity) AS latest_activity,
        COALESCE(bc.gold_badges,0)   AS gold_badges,
        COALESCE(bc.silver_badges,0) AS silver_badges,
        COALESCE(bc.bronze_badges,0) AS bronze_badges,
        tt.TagName                   AS top_tag,
        tt.tag_use_count             AS top_tag_use_count,
        /* average vote delta across the user’s posts */
        AVG(COALESCE(pva.up_votes - pva.down_votes,0))
            OVER (PARTITION BY us.user_id)               AS avg_vote_delta
    FROM user_stats us
    LEFT JOIN badge_counts bc
           ON bc.UserId = us.user_id
    LEFT JOIN (
        SELECT user_id, TagName, tag_use_count
        FROM top_tag_per_user
        WHERE rn = 1
    ) tt
           ON tt.user_id = us.user_id
    LEFT JOIN LATERAL (
        SELECT pva.up_votes, pva.down_votes
        FROM post_vote_agg pva
        WHERE pva.PostId = (
            SELECT Id
            FROM Posts p2
            WHERE p2.OwnerUserId = us.user_id
            ORDER BY p2.CreationDate DESC
            LIMIT 1
        )
        LIMIT 1
    ) pva ON TRUE
)

/* --------------------------------------------------------------
   7. Final result set: filtered users plus a grand total row
   -------------------------------------------------------------- */
SELECT *
FROM merged
WHERE Reputation > 1000
  AND (question_cnt + answer_cnt) > 10
  AND (gold_badges + silver_badges + bronze_badges) > 0
  AND top_tag IS NOT NULL
ORDER BY avg_vote_delta DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL::int                AS user_id,
    'TOTAL'                  AS DisplayName,
    SUM(Reputation)          AS Reputation,
    SUM(question_cnt)        AS question_cnt,
    SUM(answer_cnt)          AS answer_cnt,
    SUM(question_score_sum)  AS question_score_sum,
    SUM(answer_score_sum)    AS answer_score_sum,
    MAX(latest_activity)     AS latest_activity,
    SUM(gold_badges)         AS gold_badges,
    SUM(silver_badges)       AS silver_badges,
    SUM(bronze_badges)       AS bronze_badges,
    NULL::varchar            AS top_tag,
    NULL::int                AS top_tag_use_count,
    AVG(avg_vote_delta)      AS avg_vote_delta
FROM merged;
