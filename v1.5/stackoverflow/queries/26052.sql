WITH 
    TopUsers AS (
        SELECT Id, Reputation, DisplayName
        FROM Users
        ORDER BY Reputation DESC
        LIMIT 10
    ),
    PopularPosts AS (
        SELECT P.Id, P.Title, P.Score, P.ViewCount, P.Tags
        FROM Posts P
        INNER JOIN (
            SELECT PostId, COUNT(*) as VoteCount
            FROM Votes
            GROUP BY PostId
        ) V ON P.Id = V.PostId
        ORDER BY V.VoteCount DESC
        LIMIT 100
    ),
    TopAnswerers AS (
        SELECT U.Id, U.DisplayName, COUNT(*) as AnswerCount
        FROM Users U
        INNER JOIN Posts P ON U.Id = P.OwnerUserId
        WHERE P.PostTypeId = 2
        GROUP BY U.Id, U.DisplayName
        ORDER BY AnswerCount DESC
        LIMIT 10
    ),
    PopularTags AS (
        SELECT T.TagName, COUNT(*) as QuestionCount
        FROM Tags T
        INNER JOIN Posts P ON T.Id = P.Id
        WHERE P.PostTypeId = 1
        GROUP BY T.TagName
        ORDER BY QuestionCount DESC
        LIMIT 10
    )
SELECT 
    TopUsers.Id AS TU_Id,
    TopUsers.DisplayName AS TU_DisplayName,
    TopUsers.Reputation AS TU_Reputation,
    COALESCE(TopAnswerers.AnswerCount, 0) AS TA_AnswerCount
FROM TopUsers
LEFT JOIN TopAnswerers ON TopUsers.Id = TopAnswerers.Id
LEFT JOIN (SELECT Id FROM TopUsers) AS _tu ON _tu.Id = TopUsers.Id
GROUP BY 
    TopUsers.Id, TopUsers.DisplayName, TopUsers.Reputation, TopAnswerers.AnswerCount
;