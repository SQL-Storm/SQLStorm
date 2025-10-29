-- {"query": "3489.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1964} 

/*  Benchmark query – combines CTEs, window functions, outer joins,
    correlated subqueries, set operators, string ops and NULL logic   */
WITH
/* -------------------------------------------------------------
   1) Badge counts per user broken down by class (Gold=1,Silver=2,Bronze=3)
   ------------------------------------------------------------- */
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt,
        COUNT(*)                                              AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* -------------------------------------------------------------
   2) Post‑level aggregates per user (questions & answers)
   ------------------------------------------------------------- */
PostAgg AS (
    SELECT
        p.OwnerUserId                                         AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)              AS QCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)              AS ACount,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 1),0) AS QScoreSum,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 2),0) AS AScoreSum,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2),0) AS AvgAnswerScore,
        MAX(p.CreationDate)                                  AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* -------------------------------------------------------------
   3) Latest comment made by each user (correlated subquery)
   ------------------------------------------------------------- */
LatestComment AS (
    SELECT
        c.UserId,
        c.Text                                 AS CommentText,
        c.CreationDate                         AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments c
    WHERE c.UserId IS NOT NULL
),

/* -------------------------------------------------------------
   4) Top 3 tags a user has participated in (from Posts.Tags)
   ------------------------------------------------------------- */
UserTagRanks AS (
    SELECT
        p.OwnerUserId                                         AS UserId,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY COUNT(*) DESC)          AS TagRank,
        COUNT(*)                                              AS TagUseCnt
    FROM Posts p
    WHERE p.PostTypeId = 1                /* only questions */
      AND p.Tags IS NOT NULL
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
    HAVING COUNT(*) > 0
),

TopTags AS (
    SELECT
        utr.UserId,
        STRING_AGG(utr.Tag, ', ') FILTER (WHERE utr.TagRank <= 3) AS Top3Tags
    FROM UserTagRanks utr
    GROUP BY utr.UserId
),

/* -------------------------------------------------------------
   5) Users that have at least one gold badge AND a question
       with a duplicate close reason (CloseReasonId = 101)
   ------------------------------------------------------------- */
GoldAndDupClose AS (
    SELECT DISTINCT
        u.Id
    FROM Users u
    JOIN BadgeCounts bc ON bc.UserId = u.Id AND bc.GoldCnt > 0
    JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    JOIN PostHistory ph ON ph.PostId = q.Id
                       AND ph.PostHistoryTypeId = 10               -- Post Closed
    WHERE ph.Comment = '101'                                     -- Duplicate
),

/* -------------------------------------------------------------
   6) Combine everything; left‑outer joins keep users without data
   ------------------------------------------------------------- */
UserCombined AS (
    SELECT
        u.Id                                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.GoldCnt,0)      AS GoldBadges,
        COALESCE(bc.SilverCnt,0)    AS SilverBadges,
        COALESCE(bc.BronzeCnt,0)    AS BronzeBadges,
        COALESCE(pa.QCount,0)       AS QuestionCount,
        COALESCE(pa.ACount,0)       AS AnswerCount,
        COALESCE(pa.QScoreSum,0)    AS QuestionScoreSum,
        COALESCE(pa.AScoreSum,0)    AS AnswerScoreSum,
        COALESCE(pa.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(pa.LastPostDate, u.CreationDate) AS LastActivity,
        lc.CommentText,
        lc.CommentDate,
        tt.Top3Tags,
        CASE WHEN gad.Id IS NOT NULL THEN 1 ELSE 0 END               AS HasGoldAndDupClose
    FROM Users u
    LEFT JOIN BadgeCounts bc   ON bc.UserId = u.Id
    LEFT JOIN PostAgg pa       ON pa.UserId = u.Id
    LEFT JOIN (SELECT * FROM LatestComment WHERE rn = 1) lc
                                   ON lc.UserId = u.Id
    LEFT JOIN TopTags tt       ON tt.UserId = u.Id
    LEFT JOIN GoldAndDupClose gad ON gad.Id = u.Id
),

/* -------------------------------------------------------------
   7) Rank users by a composite activity score
   ------------------------------------------------------------- */
RankedUsers AS (
    SELECT
        uc.*,
        ROW_NUMBER() OVER (ORDER BY
            (uc.Reputation * 0.4
             + uc.QuestionCount * 0.2
             + uc.AnswerCount * 0.3
             + uc.GoldBadges * 5
             + uc.SilverBadges * 2
             + uc.BronzeBadges) DESC) AS ActivityRank,
        /* windowed percentile of reputation */
        PERCENT_RANK() OVER (ORDER BY uc.Reputation) AS RepPercentile
    FROM UserCombined uc
)

/* -------------------------------------------------------------
   Final result set + a summary row (set operator UNION ALL)
   ------------------------------------------------------------- */
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AvgAnswerScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.Top3Tags,
    ru.HasGoldAndDupClose,
    ru.ActivityRank,
    ru.RepPercentile,
    COALESCE(ru.CommentText, '<no recent comment>') AS RecentComment,
    CASE
        WHEN ru.CommentDate IS NULL THEN NULL
        ELSE ru.CommentDate
    END AS RecentCommentDate
FROM RankedUsers ru
WHERE ru.ActivityRank <= 500                     -- limit to top 500 for benchmark
ORDER BY ru.ActivityRank

UNION ALL

/* ----------------------------------------------------------------
   Summary row: totals/averages across the selected users
   ---------------------------------------------------------------- */
SELECT
    NULL AS UserId,
    'SUMMARY' AS DisplayName,
    SUM(Reputation)                                         AS Reputation,
    SUM(QuestionCount)                                      AS QuestionCount,
    SUM(AnswerCount)                                        AS AnswerCount,
    AVG(AvgAnswerScore)                                     AS AvgAnswerScore,
    SUM(GoldBadges)                                         AS GoldBadges,
    SUM(SilverBadges)                                       AS SilverBadges,
    SUM(BronzeBadges)                                       AS BronzeBadges,
    NULL                                                    AS Top3Tags,
    SUM(HasGoldAndDupClose)                                 AS HasGoldAndDupClose,
    NULL                                                    AS ActivityRank,
    NULL                                                    AS RepPercentile,
    NULL                                                    AS RecentComment,
    NULL                                                    AS RecentCommentDate
FROM RankedUsers
WHERE ActivityRank <= 500;
