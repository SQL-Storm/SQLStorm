-- {"query": "3929.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2559} 

/*  Comprehensive performance‑benchmark query for the StackOverflow schema  */
WITH
/* 1️⃣ Questions posted in the last year, with tags normalized to a CSV list */
q AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        REGEXP_REPLACE(p.Tags, '[><]', ',', 'g')            AS tag_csv,
        p.Score,
        p.ViewCount,
        p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1                                   -- only questions
      AND p.CreationDate >= DATE_TRUNC('year', CURRENT_DATE) - INTERVAL '1 year'
),

/* 2️⃣ Aggregate per‑user statistics, including window rank */
usr_stats AS (
    SELECT
        u.Id                                     AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(q.Id)                              AS ques_cnt,
        SUM(q.Score)                             AS total_ques_score,
        AVG(q.Score)                             AS avg_ques_score,
        COUNT(a.Id)                              AS ans_cnt,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS acc_ans_cnt,
        ROUND(
            100.0 *
            NULLIF(SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END),0) /
            NULLIF(COUNT(a.Id),0)
        ,2)                                      AS acc_rate_pct,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank,
        /* latest question title – correlated sub‑query */
        (SELECT TOP 1 p.Title
         FROM Posts p
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
         ORDER BY p.CreationDate DESC)         AS latest_ques_title
    FROM Users u
    LEFT JOIN q          ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a   ON a.PostTypeId = 2 AND a.ParentId = q.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(q.Id) > 5
),

/* 3️⃣ Badges per user – aggregated into a CSV list */
usr_badges AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ')           AS badge_list,
        MAX(b.Class)                                 AS top_badge_class
    FROM Badges b
    GROUP BY b.UserId
),

/* 4️⃣ Comment count per question (outer join later) */
cmt_cnt AS (
    SELECT
        c.PostId,
        COUNT(*) AS comment_cnt
    FROM Comments c
    GROUP BY c.PostId
),

/* 5️⃣ Tag‑level statistics (used for the UNION branch) */
tag_stats AS (
    SELECT
        t.TagName,
        t.Count                                      AS tag_use_cnt,
        COUNT(p.Id) FILTER (WHERE p.Id IS NOT NULL) AS ques_cnt,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
        SUM(v.vote_cnt)                              AS total_votes
    FROM Tags t
    LEFT JOIN Posts p
           ON p.PostTypeId = 1
          AND p.Tags LIKE '%'||t.TagName||'%'
    LEFT JOIN (
        SELECT
            v.PostId,
            COUNT(*) AS vote_cnt
        FROM Votes v
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    GROUP BY t.TagName, t.Count
    HAVING COUNT(p.Id) > 10
)

/* ============================================================================= */
/* Main result set – users with their stats + badge info + comment totals           */
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.ques_cnt,
    us.total_ques_score,
    us.avg_ques_score,
    us.ans_cnt,
    us.acc_ans_cnt,
    us.acc_rate_pct,
    us.rep_rank,
    COALESCE(ub.badge_list, 'None')               AS badges,
    ub.top_badge_class,
    COALESCE(cc.comment_total,0)                  AS total_comments_on_questions,
    us.latest_ques_title
FROM usr_stats us
LEFT JOIN usr_badges ub
       ON ub.UserId = us.user_id
LEFT JOIN (
    SELECT
        q.OwnerUserId AS uid,
        SUM(c.comment_cnt) AS comment_total
    FROM q
    LEFT JOIN cmt_cnt c ON c.PostId = q.Id
    GROUP BY q.OwnerUserId
) cc ON cc.uid = us.user_id
WHERE us.Reputation > 5000
ORDER BY us.Reputation DESC, us.acc_rate_pct DESC
LIMIT 100

/* ============================================================================= */
/* UNION branch – tag statistics, aligned to the same column list                */
UNION ALL

SELECT
    NULL                                          AS user_id,
    ts.TagName                                    AS DisplayName,
    ts.tag_use_cnt                                AS Reputation,
    ts.ques_cnt,
    NULL                                          AS total_ques_score,
    ts.avg_score                                  AS avg_ques_score,
    NULL                                          AS ans_cnt,
    NULL                                          AS acc_ans_cnt,
    NULL                                          AS acc_rate_pct,
    NULL                                          AS rep_rank,
    NULL                                          AS badges,
    NULL                                          AS top_badge_class,
    ts.total_votes                                AS total_comments_on_questions,
    NULL                                          AS latest_ques_title
FROM tag_stats ts
ORDER BY ts.ques_cnt DESC
LIMIT 50;
