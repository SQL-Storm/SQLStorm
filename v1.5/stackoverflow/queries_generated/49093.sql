-- {"query": "49093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1132} 

SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS TotalUserUpVotes,
    U.Views AS TotalUserViews,
    COUNT(DISTINCT P.Id) AS TotalQuestionsAsked,
    SUM(P.Score) AS TotalQuestionScore,
    SUM(P.ViewCount) AS TotalQuestionViews,
    COUNT(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE NULL END) AS QuestionsWithAcceptedAnswer,
    SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCount,
    COUNT(DISTINCT B.Id) AS GoldBadgesCount,
    AVG(Q_Comments.CommentCount) AS AvgCommentsPerQuestion,
    COUNT(DISTINCT Q_Commenters.CommenterUserId) AS DistinctCommentersOnQuestions,
    COUNT(DISTINCT PH_Edits.PostId) AS QuestionsEditedBySelf,
    COUNT(DISTINCT
        CASE
            WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId
            WHEN PL_Rev.LinkTypeId = 3 THEN PL_Rev.PostId
            ELSE NULL
        END
    ) AS DistinctLinkedDuplicatePosts,
    COUNT(DISTINCT CASE WHEN PH_ClosedReopened.PostId IS NOT NULL THEN P.Id ELSE NULL END) AS QuestionsClosedAndReopenedCount
FROM
    Users AS U
INNER JOIN
    Posts AS P ON U.Id = P.OwnerUserId
INNER JOIN
    PostTypes AS PT ON P.PostTypeId = PT.Id AND PT.Name = 'Question'
LEFT JOIN
    (
        SELECT PostId, COUNT(Id) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) AS Q_Comments ON P.Id = Q_Comments.PostId
LEFT JOIN
    (
        SELECT C.PostId, C.UserId AS CommenterUserId
        FROM Comments AS C
        WHERE C.UserId IS NOT NULL
        GROUP BY C.PostId, C.UserId
    ) AS Q_Commenters ON P.Id = Q_Commenters.PostId
LEFT JOIN
    Badges AS B ON U.Id = B.UserId AND B.Class = 1 -- Gold badges
LEFT JOIN
    PostHistory AS PH_Edits ON P.Id = PH_Edits.PostId
    AND PH_Edits.UserId = U.Id
    AND PH_Edits.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
LEFT JOIN
    PostLinks AS PL ON P.Id = PL.PostId AND PL.LinkTypeId = 3 -- P.Id is the source of a duplicate link
LEFT JOIN
    PostLinks AS PL_Rev ON P.Id = PL_Rev.RelatedPostId AND PL_Rev.LinkTypeId = 3 -- P.Id is the target of a duplicate link
LEFT JOIN
    (
        SELECT DISTINCT PC.PostId
        FROM PostHistory AS PC
        WHERE PC.PostHistoryTypeId = 10 -- Post Closed
        AND EXISTS (
            SELECT 1
            FROM PostHistory AS PR
            WHERE PR.PostId = PC.PostId
              AND PR.PostHistoryTypeId = 11 -- Post Reopened
              AND PR.CreationDate > PC.CreationDate
        )
    ) AS PH_ClosedReopened ON P.Id = PH_ClosedReopened.PostId
WHERE
    U.Reputation > 10000
    AND U.CreationDate <= '2022-01-01'
    AND P.CreationDate BETWEEN '2019-01-01' AND '2021-12-31'
    AND P.ContentLicense = 'CC BY-SA 4.0'
    AND (
        P.Tags LIKE '%<sql>%' OR
        P.Tags LIKE '%<database>%' OR
        P.Tags LIKE '%<performance>%' OR
        P.Tags LIKE '%<postgresql>%' OR
        P.Tags LIKE '%<mysql>%' OR
        P.Tags LIKE '%<optimization>%'
    )
    AND P.Score >= 25
    AND P.ViewCount >= 7500
    AND P.AnswerCount >= 3
    AND P.Title LIKE '%query%'
    AND P.Body LIKE '%index%'
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.Views
HAVING
    COUNT(DISTINCT P.Id) >= 7
    AND COUNT(DISTINCT B.Id) >= 2
    AND SUM(COALESCE(P.FavoriteCount, 0)) >= 75
    AND AVG(Q_Comments.CommentCount) >= 3
    AND COUNT(DISTINCT PH_Edits.PostId) >= 2
ORDER BY
    TotalQuestionScore DESC, QuestionsWithAcceptedAnswer DESC, GoldBadgesCount DESC, U.Reputation DESC, TotalUserUpVotes DESC
LIMIT 75;
