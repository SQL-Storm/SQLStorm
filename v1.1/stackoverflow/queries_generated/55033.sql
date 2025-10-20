-- {"query": "55033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1136} 

/* Benchmark query: deep analytics on tags, questions, answers, votes and user reputation */
WITH RECURSIVE TagHierarchy AS (
    /* flatten tag strings into one row per tag for each question */
    SELECT
        p.Id            AS QuestionId,
        TRIM(t)         AS Tag,
        p.CreationDate  AS QuestionDate,
        p.Score         AS QuestionScore,
        p.OwnerUserId   AS QuestionOwner
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(
            SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2),   -- strip leading/trailing <> 
            '><')) AS t
    ) AS tags
    WHERE p.PostTypeId = 1                -- only questions
),
TagStats AS (
    SELECT
        th.Tag,
        COUNT(DISTINCT th.QuestionId)                AS QuestionCount,
        AVG(th.QuestionScore)                        AS AvgQuestionScore,
        MIN(th.QuestionDate)                         AS FirstAsked,
        MAX(th.QuestionDate)                         AS LastAsked
    FROM TagHierarchy th
    GROUP BY th.Tag
),
AnswerInfo AS (
    SELECT
        q.Tag,
        a.Id                AS AnswerId,
        a.OwnerUserId       AS AnswererId,
        a.CreationDate      AS AnswerDate,
        a.Score             AS AnswerScore,
        a.CommentCount      AS AnswerComments,
        a.FavoriteCount     AS AnswerFavorites,
        ph.UserId           AS CloseVoterId,
        ph.CreationDate     AS CloseDate,
        CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END AS IsClosed
    FROM TagHierarchy q
    JOIN Posts a
        ON a.ParentId = q.QuestionId
        AND a.PostTypeId = 2                       -- answers only
    LEFT JOIN PostHistory ph
        ON ph.PostId = a.Id
        AND ph.PostHistoryTypeId IN (10,11)         -- closed / reopened events
),
AnswerAgg AS (
    SELECT
        ai.Tag,
        ai.AnswererId,
        COUNT(*)                                 AS AnswersGiven,
        SUM(ai.AnswerScore)                      AS TotalAnswerScore,
        AVG(ai.AnswerScore)                      AS AvgAnswerScore,
        COUNT(DISTINCT ai.AnswerId)              AS DistinctAnswers,
        SUM(ai.IsClosed)                         AS TimesClosed,
        MAX(ai.AnswerDate)                       AS LatestAnswerDate
    FROM AnswerInfo ai
    GROUP BY ai.Tag, ai.AnswererId
),
UserMetrics AS (
    SELECT
        u.Id                                AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                      AS UserSince,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS DownVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 END),0) AS FavoritesGiven,
        COUNT(DISTINCT p.Id)                AS PostsAuthored
    FROM Users u
    LEFT JOIN Votes v   ON v.UserId = u.Id
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
FinalReport AS (
    SELECT
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.FirstAsked,
        ts.LastAsked,
        ua.UserId,
        um.DisplayName,
        um.Reputation,
        ua.AnswersGiven,
        ua.TotalAnswerScore,
        ua.AvgAnswerScore,
        ua.TimesClosed,
        um.UpVotesGiven,
        um.DownVotesGiven,
        um.FavoritesGiven,
        um.PostsAuthored,
        ROW_NUMBER() OVER (PARTITION BY ts.Tag ORDER BY ua.TotalAnswerScore DESC, um.Reputation DESC) AS TagRank
    FROM TagStats ts
    LEFT JOIN AnswerAgg ua      ON ua.Tag = ts.Tag
    LEFT JOIN UserMetrics um    ON um.UserId = ua.AnswererId
)
SELECT
    Tag,
    QuestionCount,
    AvgQuestionScore,
    FirstAsked,
    LastAsked,
    UserId,
    DisplayName,
    Reputation,
    AnswersGiven,
    TotalAnswerScore,
    AvgAnswerScore,
    TimesClosed,
    UpVotesGiven,
    DownVotesGiven,
    FavoritesGiven,
    PostsAuthored,
    TagRank
FROM FinalReport
WHERE TagRank <= 10                -- top‑10 contributors per tag
ORDER BY Tag ASC, TagRank ASC;
