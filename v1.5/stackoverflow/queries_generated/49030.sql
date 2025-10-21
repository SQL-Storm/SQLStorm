-- {"query": "49030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 606} 

WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 20
),
UserGoldBadges AS (
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1
),
UserActiveCommenters AS (
    SELECT UserId
    FROM Comments
    GROUP BY UserId
    HAVING COUNT(DISTINCT PostId) >= 10
),
UserPostsTotalVotes AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM
        Posts P
    JOIN
        Votes V ON P.Id = V.PostId
    WHERE
        P.OwnerUserId IS NOT NULL AND V.VoteTypeId IN (2, 3)
    GROUP BY
        P.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    AVG(A.Score) AS AverageScoreOnTheirAcceptedAnswers,
    COALESCE(UPTV.UpvotesReceived, 0) AS TotalUpvotesOnAllTheirPosts,
    COALESCE(UPTV.DownvotesReceived, 0) AS TotalDownvotesOnAllTheirPosts,
    COUNT(DISTINCT Q.Id) AS TotalUniqueQuestionsAnsweredAndAccepted
FROM
    Users U
JOIN
    UserGoldBadges UGB ON U.Id = UGB.UserId
JOIN
    UserActiveCommenters UAC ON U.Id = UAC.UserId
JOIN
    Posts A ON U.Id = A.OwnerUserId
JOIN
    Posts Q ON A.ParentId = Q.Id AND Q.AcceptedAnswerId = A.Id
LEFT JOIN
    UserPostsTotalVotes UPTV ON U.Id = UPTV.UserId
WHERE
    A.PostTypeId = 2
    AND Q.PostTypeId = 1
    AND Q.AnswerCount >= 5
    AND Q.CreationDate >= NOW() - INTERVAL '5 years'
    AND EXISTS (
        SELECT 1
        FROM UNNEST(string_to_array(substring(Q.Tags, 2, length(Q.Tags)-2), '><')) AS q_tag
        JOIN PopularTags PT ON q_tag = PT.TagName
    )
GROUP BY
    U.Id, U.DisplayName, UPTV.UpvotesReceived, UPTV.DownvotesReceived
HAVING
    COUNT(A.Id) >= 1
ORDER BY
    AverageScoreOnTheirAcceptedAnswers DESC, TotalUpvotesOnAllTheirPosts DESC
LIMIT 10;
