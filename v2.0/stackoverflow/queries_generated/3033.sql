-- {"query": "3033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2236} 

/* Complex benchmarking query using CTEs, window functions, outer joins,
   correlated subqueries, set operators, string manipulation and NULL logic */

WITH ParsedTags AS (
    /* Expand the '<tag1><tag2>' string into one row per tag for each question */
    SELECT
        p.Id                     AS QuestionId,
        p.OwnerUserId            AS QuestionOwnerId,
        p.Score                  AS QuestionScore,
        p.CreationDate           AS QuestionDate,
        regexp_split_to_table(
            trim(both '<>' FROM p.Tags),
            '><'
        )                        AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
),
AnswerInfo AS (
    /* Basic answer details, linking back to the question */
    SELECT
        a.Id                     AS AnswerId,
        a.ParentId               AS QuestionId,
        a.OwnerUserId            AS AnswerOwnerId,
        a.Score                  AS AnswerScore,
        a.CreationDate           AS AnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2               -- only answers
),
UserTagStats AS (
    /* Aggregate per user‑tag pair, compute several metrics and rank */
    SELECT
        pt.TagName,
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT pt.QuestionId)                         AS QuestionsAsked,
        COUNT(DISTINCT ai.AnswerId)                           AS AnswersGiven,
        SUM(CASE WHEN ai.AnswerScore > 0 THEN ai.AnswerScore ELSE 0 END) AS PositiveAnswerScore,
        AVG(ai.AnswerScore)                                   AS AvgAnswerScore,
        MAX(ai.AnswerScore)                                   AS MaxAnswerScore,
        ROW_NUMBER() OVER (
            PARTITION BY pt.TagName
            ORDER BY u.Reputation DESC,
                     COUNT(DISTINCT ai.AnswerId) DESC
        )                                                    AS RankByRep
    FROM ParsedTags pt
    LEFT JOIN Users u          ON u.Id = pt.QuestionOwnerId
    LEFT JOIN AnswerInfo ai   ON ai.QuestionId = pt.QuestionId
    GROUP BY pt.TagName, u.Id, u.DisplayName, u.Reputation
),
GoldBadgeCounts AS (
    /* Count gold, tag‑based badges per user‑tag */
    SELECT
        b.UserId,
        t.TagName,
        COUNT(*) AS GoldBadgeCount
    FROM Badges b
    JOIN Tags t               ON b.Name = t.TagName AND b.TagBased = 1
    WHERE b.Class = 1         -- gold badges only
    GROUP BY b.UserId, t.TagName
),
TopUsersPerTag AS (
    /* Keep only the top 5 users per tag (by reputation) */
    SELECT
        uts.TagName,
        uts.UserId,
        uts.DisplayName,
        uts.Reputation,
        uts.QuestionsAsked,
        uts.AnswersGiven,
        uts.PositiveAnswerScore,
        ROUND(uts.AvgAnswerScore, 2)               AS AvgAnswerScore,
        COALESCE(gbc.GoldBadgeCount, 0)            AS GoldBadgesOnTag,
        uts.RankByRep,
        CASE WHEN uts.Reputation IS NULL THEN 'NoRep' ELSE 'HasRep' END AS RepStatus,
        CASE WHEN COALESCE(gbc.GoldBadgeCount,0) > 0 THEN 'BadgeHolder' ELSE 'NoBadge' END AS BadgeFlag
    FROM UserTagStats uts
    LEFT JOIN GoldBadgeCounts gbc
           ON gbc.UserId = uts.UserId
          AND gbc.TagName = uts.TagName
    WHERE uts.RankByRep <= 5
),
TagActivityInfo AS (
    /* Gather overall tag activity (total posts) from Tags table */
    SELECT
        t.TagName,
        t.Count AS TagTotalPosts
    FROM Tags t
)
SELECT
    fu.TagName,
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.QuestionsAsked,
    fu.AnswersGiven,
    fu.PositiveAnswerScore,
    fu.AvgAnswerScore,
    fu.GoldBadgesOnTag,
    fu.RankByRep,
    fu.RepStatus,
    fu.BadgeFlag,
    COALESCE(ti.TagTotalPosts, 0) AS TotalTagPosts
FROM TopUsersPerTag fu
FULL OUTER JOIN TagActivityInfo ti
       ON ti.TagName = fu.TagName
WHERE (ti.TagTotalPosts IS NULL OR ti.TagTotalPosts > 0)
UNION ALL
SELECT
    t.TagName,
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    0    AS QuestionsAsked,
    0    AS AnswersGiven,
    0    AS PositiveAnswerScore,
    NULL AS AvgAnswerScore,
    0    AS GoldBadgesOnTag,
    NULL AS RankByRep,
    'NoActivity' AS RepStatus,
    'NoBadge'    AS BadgeFlag,
    t.Count      AS TotalTagPosts
FROM Tags t
WHERE NOT EXISTS (
    SELECT 1
    FROM ParsedTags pt
    WHERE pt.TagName = t.TagName
)
ORDER BY TagName, RankByRep;
