-- {"query": "3799.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2291} 

/*  Benchmark query mixing CTEs, window functions, outer joins, correlated subqueries,
    set operators, string handling and NULL logic                         */
WITH
    /* explode the tag list of every question */
    ParsedTags AS (
        SELECT
            p.Id                         AS PostId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1               -- only questions
          AND p.Tags IS NOT NULL
    ),

    /* aggregate per‑tag statistics for questions */
    TagAgg AS (
        SELECT
            pt.Tag,
            COUNT(*)                                    AS QuestionCount,
            AVG(p.Score)                                AS AvgScore,
            SUM(p.ViewCount)                            AS TotalViews,
            COUNT(DISTINCT p.OwnerUserId)               AS DistinctAuthors
        FROM ParsedTags pt
        JOIN Posts p ON p.Id = pt.PostId
        GROUP BY pt.Tag
    ),

    /* keep only "heavy" tags and rank them */
    TopTags AS (
        SELECT
            t.Tag,
            t.QuestionCount,
            t.AvgScore,
            t.TotalViews,
            t.DistinctAuthors,
            ROW_NUMBER() OVER (ORDER BY t.QuestionCount DESC) AS rn
        FROM TagAgg t
        WHERE t.QuestionCount >= 100
    ),

    /* per‑question answer and vote statistics */
    AnswerStats AS (
        SELECT
            q.Id                                 AS QuestionId,
            COALESCE(a.Id, -1)                   AS FirstAnswerId,
            CASE WHEN a.Id IS NULL THEN 0 ELSE 1 END AS HasAnswer,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVoteCount,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVoteCount,
            (SELECT COUNT(DISTINCT v.UserId)
               FROM Votes v
              WHERE v.PostId = q.Id AND v.VoteTypeId IN (2,3))                           AS VoterCount
        FROM Posts q
        LEFT JOIN LATERAL (
            SELECT a.Id
            FROM Posts a
            WHERE a.ParentId = q.Id
              AND a.PostTypeId = 2               -- answers
            ORDER BY a.CreationDate ASC
            LIMIT 1
        ) a ON TRUE
        WHERE q.PostTypeId = 1
    ),

    /* user badge and reputation summary, with a string‑based tag check */
    UserBadgeStats AS (
        SELECT
            u.Id                                 AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(DISTINCT t.TagName)               AS TaggedBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Tags t
          ON t.IsModeratorOnly = 0
         AND t.IsRequired = 0
         AND EXISTS (
                SELECT 1
                  FROM Posts p
                 WHERE p.OwnerUserId = u.Id
                   AND p.Tags IS NOT NULL
                   AND p.Tags LIKE '%'||'<'||t.TagName||'>'||'%'
              )
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* combine tag‑level and user‑level info; force an outer join that may yield NULLs */
    Combined AS (
        SELECT
            tt.Tag,
            tt.QuestionCount,
            tt.AvgScore,
            tt.TotalViews,
            tt.DistinctAuthors,
            ub.Reputation,
            ub.GoldBadges,
            ub.SilverBadges,
            ub.BronzeBadges,
            ub.TaggedBadges,
            CASE
                WHEN ub.Reputation IS NULL       THEN 'No Reputation'
                WHEN ub.Reputation < 1000        THEN 'Low Rep'
                ELSE                                 'High Rep'
            END AS RepCategory
        FROM TopTags tt
        LEFT JOIN UserBadgeStats ub
               ON ub.GoldBadges > 0
              AND ub.SilverBadges > 0
        WHERE tt.rn <= 10
    )

/* final result set mixes UNION ALL, EXCEPT and an ORDER BY on a nullable column */
SELECT *
FROM Combined

UNION ALL

SELECT
    'TOTAL'                     AS Tag,
    SUM(QuestionCount)          AS QuestionCount,
    AVG(AvgScore)               AS AvgScore,
    SUM(TotalViews)             AS TotalViews,
    SUM(DistinctAuthors)        AS DistinctAuthors,
    NULL                        AS Reputation,
    NULL                        AS GoldBadges,
    NULL                        AS SilverBadges,
    NULL                        AS BronzeBadges,
    NULL                        AS TaggedBadges,
    NULL                        AS RepCategory
FROM Combined

EXCEPT

SELECT
    Tag, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Combined

ORDER BY QuestionCount DESC NULLS LAST;
