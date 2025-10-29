-- {"query": "1571.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3086}
WITH UserActivitySnapshot AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsByOwner,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
        EXTRACT(EPOCH FROM (MAX(P.LastActivityDate) - MIN(P.CreationDate))) / 86400.0 AS DaysBetweenFirstAndLastPostActivity,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments AS C ON U.Id = C.UserId
    WHERE
        U.Reputation >= 100
        AND U.LastAccessDate >= '2020-01-01'
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING
        COUNT(P.Id) > 5 OR COUNT(C.Id) > 2
),
PostDetailsWithTags AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.AcceptedAnswerId,
        P.ParentId,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        COALESCE(array_length(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><'), 1), 0) AS NumberOfTags,
        string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><') AS TagsArray,
        CASE
            WHEN P.PostTypeId = 1 AND P.ViewCount > 0 THEN CAST(COALESCE(P.AnswerCount, 0) AS DECIMAL) / P.ViewCount
            ELSE 0
        END AS AnswerToViewRatio,
        COALESCE(P.FavoriteCount, 0) AS EffectiveFavoriteCount,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId IN (2, 3)) AS TotalUpOrDownVotes,
        EXISTS (
            SELECT 1
            FROM PostHistory AS PH
            WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
        ) AS WasEverClosed,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate
    FROM
        Posts AS P
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= '2020-01-01'
),
CommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(DISTINCT C.UserId) AS UniqueCommenters,
        MAX(C.CreationDate) AS LastCommentDate
    FROM
        Comments AS C
    GROUP BY
        C.PostId
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE NULL END) AS LinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE NULL END) AS DuplicatePostsCount,
        STRING_AGG(CASE WHEN PL.LinkTypeId = 3 THEN CAST(PL.RelatedPostId AS VARCHAR) ELSE NULL END, ',') AS DuplicatePostIds
    FROM
        PostLinks AS PL
    GROUP BY
        PL.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationQuintile,
    PDT.PostId,
    PDT.PostTypeId,
    PDT.Title AS PostTitle,
    PDT.PostCreationDate,
    PDT.PostScore,
    PDT.ViewCount,
    PDT.NumberOfTags,
    PDT.TagsArray,
    PDT.AnswerToViewRatio,
    PDT.EffectiveFavoriteCount,
    PDT.TotalUpOrDownVotes,
    PDT.WasEverClosed,
    COALESCE(CS.TotalCommentsOnPost, 0) AS TotalCommentsOnThisPost,
    COALESCE(CS.TotalCommentScore, 0) AS TotalCommentScoreOnThisPost,
    COALESCE(PLS.LinkedPostsCount, 0) AS IncomingLinks,
    COALESCE(PLS.DuplicatePostsCount, 0) AS IsDuplicateOfCount,
    PLS.DuplicatePostIds,
    (EXTRACT(EPOCH FROM (PDT.PostCreationDate - PDT.PreviousPostCreationDate)) / 3600.0) AS HoursSincePreviousPostBySameUser,
    AVG(PDT.PostScore) OVER (PARTITION BY UAS.ReputationQuintile) AS AvgScoreInReputationQuintile,
    CASE
        WHEN PDT.AnswerToViewRatio > 0.05 AND PDT.PostScore > 10 THEN 'High Engagement Question'
        WHEN PDT.WasEverClosed THEN 'Closed Question'
        WHEN PDT.NumberOfTags = 0 AND PDT.PostScore < 0 THEN 'Poorly Tagged/Received Question'
        ELSE 'Other Question'
    END AS PostCategory,
    (
        SELECT AVG(A_SUB.Score)
        FROM Posts AS A_SUB
        WHERE A_SUB.ParentId = PDT.PostId AND A_SUB.PostTypeId = 2
          AND A_SUB.OwnerUserId != PDT.OwnerUserId
          AND A_SUB.CreationDate < PDT.LastActivityDate
    ) AS AvgAnswerScoreForQuestionByOthers,
    NULLIF(UAS.UserUpVotes - UAS.UserDownVotes, 0) AS UserNetVotesScore,
    (
        SELECT
            AVG(WPP.Score)
        FROM
            Tags AS T_PRIMARY
        INNER JOIN
            Posts AS WPP ON T_PRIMARY.WikiPostId = WPP.Id
        WHERE
            PDT.TagsArray IS NOT NULL AND array_length(PDT.TagsArray, 1) > 0 AND T_PRIMARY.TagName = PDT.TagsArray[1]
        GROUP BY T_PRIMARY.TagName
    ) AS AvgWikiPostScoreForPrimaryTag,
    CAST(NULL AS INT) AS AcceptedAnswerParentQuestionScore,
    PDT.ViewCount AS QuestionViewCount,
    PDT.AnswerCount AS QuestionAnswerCount
FROM
    UserActivitySnapshot AS UAS
INNER JOIN
    PostDetailsWithTags AS PDT ON UAS.UserId = PDT.OwnerUserId
LEFT JOIN
    CommentSummary AS CS ON PDT.PostId = CS.PostId
LEFT JOIN
    PostLinkSummary AS PLS ON PDT.PostId = PLS.PostId
WHERE
    PDT.PostTypeId = 1
    AND PDT.PostScore >= -5
    AND UAS.TotalPostsByOwner >= 3
    AND ( (PDT.TagsArray[1] LIKE 'sql%') OR PDT.TagsArray[1] IS NULL )

UNION ALL

SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationQuintile,
    PDT.PostId,
    PDT.PostTypeId,
    PDT.Title AS PostTitle,
    PDT.PostCreationDate,
    PDT.PostScore,
    CAST(NULL AS INT) AS ViewCount,
    PDT.NumberOfTags,
    PDT.TagsArray,
    CAST(NULL AS DECIMAL) AS AnswerToViewRatio,
    PDT.EffectiveFavoriteCount,
    PDT.TotalUpOrDownVotes,
    PDT.WasEverClosed,
    COALESCE(CS.TotalCommentsOnPost, 0) AS TotalCommentsOnThisPost,
    COALESCE(CS.TotalCommentScore, 0) AS TotalCommentScoreOnThisPost,
    COALESCE(PLS.LinkedPostsCount, 0) AS IncomingLinks,
    COALESCE(PLS.DuplicatePostsCount, 0) AS IsDuplicateOfCount,
    PLS.DuplicatePostIds,
    (EXTRACT(EPOCH FROM (PDT.PostCreationDate - PDT.PreviousPostCreationDate)) / 3600.0) AS HoursSincePreviousPostBySameUser,
    AVG(PDT.PostScore) OVER (PARTITION BY UAS.ReputationQuintile) AS AvgScoreInReputationQuintile,
    CASE
        WHEN PDT.PostScore > 5 AND Q.AcceptedAnswerId = PDT.PostId THEN 'Accepted High Score Answer'
        WHEN PDT.PostScore > 0 AND PDT.AcceptedAnswerId IS NULL THEN 'Valuable Unaccepted Answer'
        ELSE 'Other Answer'
    END AS PostCategory,
    CAST(NULL AS NUMERIC) AS AvgAnswerScoreForQuestionByOthers,
    NULLIF(UAS.UserUpVotes - UAS.UserDownVotes, 0) AS UserNetVotesScore,
    CAST(NULL AS NUMERIC) AS AvgWikiPostScoreForPrimaryTag,
    (
        SELECT Q_PARENT.Score FROM Posts AS Q_PARENT WHERE Q_PARENT.Id = PDT.ParentId AND Q_PARENT.PostTypeId = 1
    ) AS AcceptedAnswerParentQuestionScore,
    CAST(NULL AS INT) AS QuestionViewCount,
    CAST(NULL AS INT) AS QuestionAnswerCount
FROM
    UserActivitySnapshot AS UAS
INNER JOIN
    PostDetailsWithTags AS PDT ON UAS.UserId = PDT.OwnerUserId
LEFT JOIN
    CommentSummary AS CS ON PDT.PostId = CS.PostId
LEFT JOIN
    PostLinkSummary AS PLS ON PDT.PostId = PLS.PostId
LEFT JOIN
    Posts AS Q ON PDT.ParentId = Q.Id AND Q.PostTypeId = 1
WHERE
    PDT.PostTypeId = 2
    AND PDT.PostScore >= -5
    AND UAS.TotalPostsByOwner >= 3
ORDER BY
    Reputation DESC, PostCreationDate DESC, PostScore DESC
LIMIT 1000;