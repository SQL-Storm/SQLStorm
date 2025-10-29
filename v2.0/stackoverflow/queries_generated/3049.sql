-- {"query": "3049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1852} 

/*  Performance‑Benchmarking Query – combines CTEs, window functions, correlated subqueries,
    outer joins, set operators, rich predicates, string handling and NULL logic                */

WITH
/* --------------------------------------------------------------
   1️⃣  Question‑level aggregates (scores, views, tags, etc.)
   -------------------------------------------------------------- */
QuestionStats AS (
    SELECT
        q.Id                                          AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(q.FavoriteCount,0)                   AS FavoriteCnt,
        COALESCE(q.AnswerCount,0)                     AS AnswerCnt,
        q.Tags,
        /* Extract first tag for demo purposes */
        CASE
            WHEN q.Tags IS NOT NULL
                 THEN split_part(substring(q.Tags from 2 for char_length(q.Tags)-2), '><', 1)
            ELSE NULL
        END                                           AS FirstTag,
        /* Normalised popularity metric */
        (q.Score * 10 + COALESCE(q.ViewCount,0) / 1000) AS PopularityScore
    FROM Posts q
    WHERE q.PostTypeId = 1                                 -- only questions
),

/* --------------------------------------------------------------
   2️⃣  User activity snapshot (reputation, badges, vote‑sum)
   -------------------------------------------------------------- */
UserActivity AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                               AS UserSince,
        /* Total gold/silver/bronze badge count per user */
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS BronzeBadges,
        /* Net vote score on posts owned by the user */
        COALESCE( (
            SELECT SUM(v.VoteTypeId = 2) - SUM(v.VoteTypeId = 3)
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE p.OwnerUserId = u.Id
        ), 0)                                        AS NetVoteScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
),

/* --------------------------------------------------------------
   3️⃣  Tag‑level summary (question count, avg score, latest activity)
   -------------------------------------------------------------- */
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                   AS QuestionCount,
        AVG(p.Score)                                  AS AvgScore,
        MAX(p.LastActivityDate)                       AS LastActivity,
        STRING_AGG(DISTINCT CONCAT('Q', p.Id), ',')   AS SampleQuestionIds
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
                 AND p.PostTypeId = 1
    GROUP BY t.TagName
),

/* --------------------------------------------------------------
   4️⃣  Recent close‑vote activities (using PostHistory)
   -------------------------------------------------------------- */
RecentCloses AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        ph.UserId,
        CAST(ph.Comment AS INT)                       AS CloseReasonId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                    -- Post Closed
      AND ph.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),

/* --------------------------------------------------------------
   5️⃣  Combined question‑answer set (union of questions and answers)
   -------------------------------------------------------------- */
QA_Union AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        NULL AS ParentId,
        NULL AS AcceptedAnswerId
    FROM Posts p
    WHERE p.PostTypeId = 1                                 -- questions
    UNION ALL
    SELECT
        a.Id,
        a.PostTypeId,
        NULL AS Title,
        a.Body,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.ParentId,
        NULL AS AcceptedAnswerId
    FROM Posts a
    WHERE a.PostTypeId = 2                                 -- answers
)

/* --------------------------------------------------------------
   Main query – bring everything together
   -------------------------------------------------------------- */
SELECT
    qs.QuestionId,
    qs.Title,
    qs.CreationDate                                   AS QCreated,
    qs.PopularityScore,
    qs.FirstTag,
    /* Rank of the question within its first‑tag group by popularity */
    RANK() OVER (PARTITION BY qs.FirstTag ORDER BY qs.PopularityScore DESC) AS TagRank,
    /* Owner details – left join to allow for deleted users (NULL) */
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.NetVoteScore,
    /* Close‑vote info – take the most recent close if any */
    rc.CloseReasonId,
    rc.CreationDate                                   AS CloseDate,
    /* Correlated subquery: count of comments per question */
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qs.QuestionId) AS CommentCount,
    /* Set‑operator result: total number of related posts (questions + answers) */
    (SELECT COUNT(*) FROM QA_Union qau WHERE qau.Id = qs.QuestionId OR qau.ParentId = qs.QuestionId) AS TotalRelatedPosts,
    /* Tag metrics – left join may produce NULL for tags not in Tag table */
    tm.QuestionCount                                 AS TagQuestionCount,
    tm.AvgScore                                       AS TagAvgScore,
    tm.LastActivity                                   AS TagLastActivity,
    tm.SampleQuestionIds
FROM QuestionStats qs
LEFT JOIN UserActivity ua
       ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = qs.QuestionId)
LEFT JOIN RecentCloses rc
       ON rc.PostId = qs.QuestionId AND rc.rn = 1
LEFT JOIN TagMetrics tm
       ON tm.TagName = qs.FirstTag
WHERE
    /* Complex predicate mixing arithmetic, string and NULL logic */
    (qs.PopularityScore > 50
     OR (qs.FirstTag IS NOT NULL AND qs.FirstTag ILIKE '%sql%')
     OR qs.Title IS NULL)
  AND (qs.AnswerCnt = 0 OR qs.FavoriteCnt > 0)
ORDER BY qs.PopularityScore DESC
LIMIT 100
OFFSET 0;
