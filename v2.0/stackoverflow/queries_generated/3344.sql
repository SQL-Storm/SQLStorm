-- {"query": "3344.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1367} 

/*  Benchmark‑heavy query: tag‑centric statistics with deep joins, CTEs, window functions, 
    set operators, string manipulation and NULL logic. */
WITH RECURSIVE TagTokens AS (
    /* explode the Tags XML‑ish list into individual tag strings */
    SELECT
        p.Id               AS PostId,
        p.PostTypeId,
        TRIM(BOTH '><' FROM t.tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(
        COALESCE(p.Tags, ''), 
        '><'
    ) AS t(tag)
    WHERE p.PostTypeId = 1                     -- only questions
),
TagAggregates AS (
    SELECT
        tt.TagName,
        COUNT(*)                                     AS QuestionCount,
        AVG(p.Score)                                 AS AvgQuestionScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.AnswerCount) 
                                                       AS MedianAnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) 
                                                       AS UpVoteTotal,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) 
                                                       AS DownVoteTotal,
        MAX(p.CreationDate)                         AS MostRecentQuestion,
        MIN(p.CreationDate)                         AS EarliestQuestion
    FROM TagTokens tt
    JOIN Posts p          ON p.Id = tt.PostId
    LEFT JOIN Votes v     ON v.PostId = p.Id
    GROUP BY tt.TagName
),
TopTags AS (
    SELECT
        ta.*,
        RANK() OVER (ORDER BY ta.QuestionCount DESC) AS TagRank
    FROM TagAggregates ta
    WHERE ta.QuestionCount > 0
),
UserReps AS (
    SELECT
        u.Id               AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS rn
    FROM Users u
),
TopUsersPerTag AS (
    SELECT
        tt.TagName,
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY ur.Reputation DESC) AS rn_user
    FROM TagTokens tt
    JOIN Posts p      ON p.Id = tt.PostId
    JOIN Users u      ON u.Id = p.OwnerUserId
    JOIN UserReps ur  ON ur.UserId = u.Id
    WHERE ur.rn = 1
),
RecentBadges AS (
    SELECT
        b.UserId,
        b.Name               AS BadgeName,
        b.Date               AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn_badge
    FROM Badges b
),
TagBadges AS (
    SELECT
        t.TagName,
        rb.BadgeName,
        rb.BadgeDate
    FROM TopTags t
    LEFT JOIN RecentBadges rb ON rb.rn_badge = 1
        AND rb.UserId = (
            SELECT TOP 1 p.OwnerUserId
            FROM Posts p
            JOIN TagTokens tt ON tt.PostId = p.Id
            WHERE tt.TagName = t.TagName
            ORDER BY p.Score DESC NULLS LAST
        )
)
SELECT
    tt.TagName,
    tt.QuestionCount,
    ROUND(tt.AvgQuestionScore,2)                AS AvgScore,
    COALESCE(tt.MedianAnswerCount,0)            AS MedianAnswers,
    tt.UpVoteTotal - tt.DownVoteTotal           AS NetVotes,
    tt.MostRecentQuestion                       AS LastQuestionDate,
    tt.EarliestQuestion                         AS FirstQuestionDate,
    tup.DisplayName                             AS TopUserByReputation,
    tup.Reputation                              AS TopUserReputation,
    tb.BadgeName                                AS LatestBadgeOnTopUser,
    tb.BadgeDate                                AS LatestBadgeDate,
    CASE 
        WHEN tt.QuestionCount >= 1000 THEN 'HOT'
        WHEN tt.QuestionCount >= 500  THEN 'WARM'
        ELSE 'COOL'
    END                                          AS HeatLevel
FROM TopTags tt
LEFT JOIN TopUsersPerTag tup
    ON tup.TagName = tt.TagName
   AND tup.rn_user = 1
LEFT JOIN TagBadges tb
    ON tb.TagName = tt.TagName
WHERE tt.TagRank <= 10
UNION ALL
/*  Include tags that have no questions (to test outer‑join performance) */
SELECT
    tg.TagName,
    0                                      AS QuestionCount,
    NULL                                   AS AvgScore,
    NULL                                   AS MedianAnswers,
    0                                      AS NetVotes,
    NULL                                   AS LastQuestionDate,
    NULL                                   AS FirstQuestionDate,
    NULL                                   AS TopUserByReputation,
    NULL                                   AS TopUserReputation,
    NULL                                   AS LatestBadgeOnTopUser,
    NULL                                   AS LatestBadgeDate,
    'NO QUES'                              AS HeatLevel
FROM Tags tg
WHERE NOT EXISTS (
    SELECT 1 FROM TagTokens tt WHERE tt.TagName = tg.TagName
)
ORDER BY QuestionCount DESC NULLS LAST, TagName;
