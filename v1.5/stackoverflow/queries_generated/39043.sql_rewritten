-- {"query": "39043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2413} 
WITH
-- Top users by reputation over the last year, plus their activity counts
ActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)   AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)   AS AnswersGiven,
        COUNT(DISTINCT c.Id)                                      AS CommentsWritten,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)             AS RankByReputation
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    LEFT JOIN Comments c
        ON c.UserId = u.Id
       AND c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- Top tags by question count (and their average question score) over the last year
TopTags AS (
    SELECT
        t.TagName,
        COUNT(q.Id)               AS QuestionCount,
        AVG(q.Score)              AS AvgQuestionScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(q.Id) DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts q
        ON q.PostTypeId = 1
       AND q.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
       AND POSITION('<' || t.TagName || '>' IN q.Tags) > 0
    GROUP BY t.TagName
),
-- Matrix of how many contributions each top user made to each tag in the last year
UserTagMatrix AS (
    SELECT
        au.Id     AS UserId,
        taglist.TagName,
        COUNT(*)  AS Contributions
    FROM ActiveUsers au
    JOIN Posts p
        ON p.OwnerUserId = au.Id
       AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    JOIN LATERAL (
        SELECT unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags)-2),
                '><'
            )
        ) AS TagName
    ) AS taglist ON TRUE
    GROUP BY au.Id, taglist.TagName
)
SELECT
    au.Id              AS UserId,
    au.DisplayName     AS UserName,
    au.Reputation,
    au.QuestionsAsked,
    au.AnswersGiven,
    au.CommentsWritten,
    tt.TagName,
    tt.QuestionCount,
    ROUND(tt.AvgQuestionScore,2)  AS AvgQuestionScore,
    COALESCE(utm.Contributions,0)  AS ContributionsToTag
FROM ActiveUsers au
-- restrict to top 10 users by reputation
JOIN LATERAL (
    SELECT TagName, QuestionCount, AvgQuestionScore
    FROM TopTags
    WHERE TagRank <= 5
) tt ON TRUE
LEFT JOIN UserTagMatrix utm
    ON utm.UserId = au.Id
   AND utm.TagName = tt.TagName
WHERE au.RankByReputation <= 10
ORDER BY au.RankByReputation, tt.QuestionCount DESC;