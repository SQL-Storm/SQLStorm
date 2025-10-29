-- {"query": "3422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1537} 

/*  Performance‑benchmarking query mixing CTEs, outer joins, correlated sub‑queries,
    window functions, set operators, complex expressions and NULL logic.            */
WITH
/* 1️⃣ Top 100 users by reputation and recent activity */
top_users AS (
    SELECT
        u.Id                                            AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(MAX(p.CreationDate), u.CreationDate)    AS last_post_date,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, 
                                      COALESCE(MAX(p.CreationDate), u.CreationDate) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 5
    ORDER BY rn
    LIMIT 100
),

/* 2️⃣ Recent questions (last 30 days) with tag array parsed */
recent_questions AS (
    SELECT
        q.Id                                 AS q_id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.Tags,
        /* split tags into a sorted array for later joins */
        ARRAY_AGG(TRIM(t)) WITHIN GROUP (ORDER BY TRIM(t)) AS tag_list
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t
    ) AS tag_split
    WHERE q.PostTypeId = 1                                     -- Question
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.CreationDate, q.Tags
),

/* 3️⃣ Badge aggregation per user (only gold & silver) */
user_badge_agg AS (
    SELECT
        b.UserId                                          AS user_id,
        COUNT(*) FILTER (WHERE b.Class = 1)               AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)               AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)               AS bronze_cnt,
        STRING_AGG(DISTINCT b.Name, ';')                  AS badge_names
    FROM Badges b
    WHERE b.Class IN (1,2,3)
    GROUP BY b.UserId
),

/* 4️⃣ Vote summary per post (upvotes minus downvotes) */
post_vote_summary AS (
    SELECT
        v.PostId                                      AS post_id,
        SUM(CASE WHEN vt.Id = 2 THEN 1
                 WHEN vt.Id = 3 THEN -1
                 ELSE 0 END)                         AS net_score,
        COUNT(*) FILTER (WHERE vt.Id = 5)            AS favorites,
        MAX(v.CreationDate)                          AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),

/* 5️⃣ Posts that are linked or marked duplicate (using set operator) */
linked_or_duplicate AS (
    SELECT
        pl.PostId      AS src_id,
        pl.RelatedPostId AS tgt_id,
        lt.Name        AS link_type
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Id IN (1,3)                     -- 1 = Linked, 3 = Duplicate
),

/* 6️⃣ Correlated sub‑query to fetch the most recent edit comment per post */
latest_edit_comment AS (
    SELECT
        ph.PostId,
        ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)            -- Edit Title/Body/Tags
      AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate)
            FROM PostHistory ph2
            WHERE ph2.PostId = ph.PostId
              AND ph2.PostHistoryTypeId IN (4,5,6)
      )
),

/* 7️⃣ Combine question, vote, tag and edit data */
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
        ARRAY_LENGTH(q.tag_list,1) AS tag_count
    FROM recent_questions q
    LEFT JOIN post_vote_summary vs ON vs.post_id = q.q_id
    LEFT JOIN latest_edit_comment le ON le.PostId = q.q_id
),

/* 8️⃣ Answers per question with row_number to get top‑voted answer */
answer_rank AS (
    SELECT
        a.ParentId                           AS question_id,
        a.Id                                 AS answer_id,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2                       -- Answer
),

/* 9️⃣ Final union of two interest sets: high‑score questions and users with gold badges */
high_score_questions AS (
    SELECT
        qd.q_id               AS entity_id,
        qd.Title              AS description,
        qd.question_score    AS metric,
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

SELECT *
FROM high_score_questions
UNION ALL
SELECT *
FROM gold_badge_users
ORDER BY metric DESC, extra_metric DESC
LIMIT 200;
