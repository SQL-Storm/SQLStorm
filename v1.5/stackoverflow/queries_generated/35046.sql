-- {"query": "35046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 816} 
WITH
TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS Rank
    FROM
        Users U
        JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.Reputation > 0
    GROUP BY
        U.Id, U.DisplayName, U.Reputation
    HAVING
        COUNT(DISTINCT P.Id) > 50
),
PopularTags AS (
    SELECT
        T.TagName,
        T.Count,
        ROW_NUMBER() OVER (ORDER BY T.Count DESC) AS Rank
    FROM
        Tags T
    WHERE
        T.Count > 100
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.TotalPosts,
    TU.Questions,
    TU.Answers,
    PT.TagName AS MostUsedTag,
    PT.Count AS TagUsage,
    COALESCE(SUBQ.AvgScore, 0) AS AvgScoreOnTag,
    COALESCE(SUBQ.MaxScore, 0) AS MaxScoreOnTag,
    COALESCE(SUBQ.PostsWithTag, 0) AS PostsWithTag,
    (SELECT COUNT(DISTINCT Q.Id)
         FROM Posts Q
         WHERE Q.OwnerUserId = TU.UserId
           AND Q.PostTypeId = 1
           AND Q.AnswerCount >= 1
           AND Q.AcceptedAnswerId IS NOT NULL
    ) AS AnsweredQuestions
FROM
    TopUsers TU
    LEFT JOIN (
        SELECT
            P.OwnerUserId,
            UPPER(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS TagName,
            COUNT(*) AS PostsWithTag,
            AVG(P.Score) AS AvgScore,
            MAX(P.Score) AS MaxScore
        FROM
            Posts P
        WHERE
            P.Tags IS NOT NULL
        GROUP BY
            P.OwnerUserId, UPPER(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')))
    ) SUBQ ON SUBQ.OwnerUserId = TU.UserId
    LEFT JOIN (
        SELECT DISTINCT ON (P.OwnerUserId)
            P.OwnerUserId,
            UPPER(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS TagName,
            COUNT(*) OVER (PARTITION BY P.OwnerUserId, UPPER(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')))) AS TagUsage
        FROM
            Posts P
        WHERE
            P.Tags IS NOT NULL
    ) PT ON PT.OwnerUserId = TU.UserId
WHERE
    TU.Rank <= 50
    AND PT.TagName = SUBQ.TagName
    AND PT.TagUsage = (
        SELECT MAX(TagUsage) FROM (
            SELECT
                UPPER(unnest(string_to_array(substring(P1.Tags, 2, length(P1.Tags)-2), '><'))) AS TagName,
                COUNT(*) AS TagUsage
            FROM
                Posts P1
            WHERE
                P1.OwnerUserId = TU.UserId
                AND P1.Tags IS NOT NULL
            GROUP BY
                UPPER(unnest(string_to_array(substring(P1.Tags, 2, length(P1.Tags)-2), '><')))
        ) AS TagCounts
    )
ORDER BY
    TU.Reputation DESC, TU.UserId
LIMIT 50;