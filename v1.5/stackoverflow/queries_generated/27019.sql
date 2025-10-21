-- {"query": "27019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 836} 

WITH UserMetrics AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        MAX(P.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        LastPostDate,
        ReputationRank
    FROM
        UserMetrics
    WHERE
        LastPostDate > DATEADD(MONTH, -6, GETDATE())
),
TopTags AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        COUNT(PT.Id) AS TagUsageCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(PT.Id) DESC) AS TagRank
    FROM
        Tags T
    JOIN
        Posts PT ON T.Id = PT.Tags
    GROUP BY
        T.Id, T.TagName
)
SELECT
        U.UserId,
        U.DisplayName,
        U.Reputation,
        U.UserCreationDate,
        A.TotalPosts,
        A.TotalQuestions,
        A.TotalAnswers,
        A.QuestionScore,
        A.AnswerScore,
        A.ReputationRank,
        STRING_AGG(T.TagName, ', ') AS TopTags,
        MIN(TT.TagUsageCount) AS MinTagUsage,
        MAX(TT.TagUsageCount) AS MaxTagUsage
    FROM
        ActiveUsers A
    JOIN
        Users U ON A.UserId = U.Id
    LEFT JOIN
        Posts P ON A.UserId = P.OwnerUserId
    LEFT JOIN
        TopTags TT ON P.Tags LIKE CONCAT('%<', TT.TagName, '>%')
    LEFT JOIN
        Tags T ON TT.TagId = T.Id
    GROUP BY
        U.UserId, U.DisplayName, U.Reputation, U.UserCreationDate, A.TotalPosts, A.TotalQuestions, A.TotalAnswers, A.QuestionScore, A.AnswerScore, A.ReputationRank
    HAVING
        COUNT(DISTINCT P.Id) > 10 AND A.ReputationRank <= 100
    ORDER BY
        A.ReputationRank, U.Reputation DESC, U.UserCreationDate;
