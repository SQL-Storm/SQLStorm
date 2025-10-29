WITH PopularTags AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        COUNT(P.Id) AS PostCount
    FROM Tags T
    JOIN Posts P ON P.Tags IS NOT NULL AND EXISTS (
        SELECT 1
        FROM UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags)-2)), '><')) AS PostTag
        WHERE PostTag = T.TagName
    )
    WHERE P.PostTypeId = 1
      AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    GROUP BY T.TagName, T.Id
    HAVING COUNT(P.Id) > 750
),
ExpertUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COUNT(DISTINCT P_Ans.Id) AS AnswerCount,
        COUNT(DISTINCT P_Que.Id) AS QuestionCount,
        SUM(CASE WHEN P_Ans.Score IS NOT NULL THEN P_Ans.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN P_Que.Score IS NOT NULL THEN P_Que.Score ELSE 0 END) AS TotalQuestionScore
    FROM Users U
    LEFT JOIN Votes V ON V.UserId = U.Id
    LEFT JOIN Posts P_Ans ON P_Ans.OwnerUserId = U.Id AND P_Ans.PostTypeId = 2
    LEFT JOIN Posts P_Que ON P_Que.OwnerUserId = U.Id AND P_Que.PostTypeId = 1
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
TagExperts AS (
    SELECT
        pt.TagId,
        pt.TagName,
        eu.UserId,
        eu.DisplayName,
        eu.Reputation,
        eu.AnswerCount,
        eu.TotalAnswerScore,
        COUNT(a.Id) AS AnswersInTag,
        SUM(a.Score) AS ScoreInTag
    FROM PopularTags pt
    JOIN Posts a ON a.PostTypeId = 2
    JOIN Posts q ON q.Id = a.ParentId
    JOIN ExpertUsers eu ON eu.UserId = a.OwnerUserId
    WHERE q.Tags IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags)-2)), '><')) AS PostTag
        WHERE PostTag = pt.TagName
      )
    GROUP BY pt.TagId, pt.TagName, eu.UserId, eu.DisplayName, eu.Reputation, eu.AnswerCount, eu.TotalAnswerScore
),
TopTagExperts AS (
    SELECT
        te.TagId,
        te.TagName,
        te.UserId,
        te.DisplayName,
        te.Reputation,
        te.AnswersInTag,
        te.ScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY te.TagId ORDER BY te.ScoreInTag DESC, te.AnswersInTag DESC) AS rn
    FROM TagExperts te
)
SELECT
    pt.TagId,
    pt.TagName,
    pt.PostCount,
    tte.UserId,
    tte.DisplayName,
    tte.Reputation,
    tte.AnswersInTag,
    tte.ScoreInTag
FROM PopularTags pt
LEFT JOIN TopTagExperts tte ON tte.TagId = pt.TagId AND tte.rn = 1
ORDER BY pt.PostCount DESC, pt.TagName;