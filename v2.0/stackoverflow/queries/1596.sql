-- {"query": "1596.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3052}
WITH UserStatsAndVotes AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P_OWNED.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P_OWNED.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN P_OWNED.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P_OWNED.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN P_OWNED.Id END) AS TotalAnswersOwned,
        SUM(COALESCE(P_OWNED.Score, 0)) AS TotalScoreOnOwnedPosts,
        (
            SELECT COUNT(V.Id)
            FROM Votes V
            WHERE V.PostId IN (SELECT P2.Id FROM Posts P2 WHERE P2.OwnerUserId = U.Id)
              AND V.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')
        ) AS UpvotesReceivedOnOwnedPosts,
        (
            SELECT COUNT(V.Id)
            FROM Votes V
            WHERE V.PostId IN (SELECT P2.Id FROM Posts P2 WHERE P2.OwnerUserId = U.Id)
              AND V.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod')
        ) AS DownvotesReceivedOnOwnedPosts,
        (
            SELECT COUNT(DISTINCT Q.Id)
            FROM Posts Q
            JOIN Posts A ON Q.AcceptedAnswerId = A.Id
            WHERE A.OwnerUserId = U.Id
              AND Q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
        ) AS AnswersAcceptedCount,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LatestBadgeDate,
        (U.Reputation * 0.1 + U.UpVotes * 0.05 + U.Views * 0.01 + COUNT(DISTINCT P_OWNED.Id) * 2 + COUNT(DISTINCT B.Id) * 5) AS UserActivityScore
    FROM Users U
    LEFT JOIN Posts P_OWNED ON U.Id = P_OWNED.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementSummary AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.ParentId,
        COALESCE(P.ClosedDate, P.CommunityOwnedDate) AS StatusChangeDate,
        (
            SELECT C.Text
            FROM Comments C
            WHERE C.PostId = P.Id
            ORDER BY C.CreationDate DESC
            LIMIT 1
        ) AS LatestCommentText,
        COALESCE((SELECT AVG(CAST(C.Score AS DECIMAL(10,2))) FROM Comments C WHERE C.PostId = P.Id), 0.0) AS AverageCommentScore,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreWithinType,
        SUM(P.ViewCount) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeOwnerViewCount,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
),
TagInfoExtractor AS (
    SELECT
        P.Id AS PostId,
        (STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR CHAR_LENGTH(P.Tags) - 2), '><'))[1] AS FirstTagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags <> '$$' AND CHAR_LENGTH(P.Tags) > 2
),
PostPrimaryTag AS (
    SELECT
        TIE.PostId,
        TIE.FirstTagName AS TagName,
        T.Id AS TagId,
        T.Count AS TagUseCount
    FROM TagInfoExtractor TIE
    LEFT JOIN Tags T ON TIE.FirstTagName = T.TagName
)
SELECT
    'TopQuestion' AS RecordType,
    USV.UserId,
    USV.DisplayName,
    USV.Reputation,
    PES.PostId,
    PES.PostTypeId,
    PT.Name AS PostTypeName,
    PES.PostCreationDate,
    PES.PostScore,
    PES.ViewCount AS PostViewCount,
    PES.AnswerCount AS QuestionAnswerCount,
    PES.CommentCount AS PostCommentCount,
    PES.FavoriteCount AS PostFavoriteCount,
    PES.Title AS PostTitle,
    PES.Tags AS PostTags,
    PES.StatusChangeDate,
    PES.LatestCommentText,
    PES.AverageCommentScore,
    PPT.TagName AS PrimaryTagName,
    PPT.TagUseCount,
    COALESCE(CR.Name, 'N/A') AS CloseReason,
    CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - PES.PostCreationDate)) / 3600 / 24 AS INT) AS PostAgeInDays,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked')) AS LinkedPostCount,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.RelatedPostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked')) AS LinkedByPostCount,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')) AS DuplicatePostCount,
    MD5(UPPER(COALESCE(USV.DisplayName, 'UNKNOWN') || COALESCE(PES.Title, 'NO_TITLE') || CAST(PES.PostCreationDate AS TEXT))) AS ContentHash
FROM UserStatsAndVotes USV
INNER JOIN PostEngagementSummary PES ON USV.UserId = PES.OwnerUserId
LEFT JOIN PostTypes PT ON PES.PostTypeId = PT.Id
LEFT JOIN PostPrimaryTag PPT ON PES.PostId = PPT.PostId
LEFT JOIN PostHistory PH_Close ON PES.PostId = PH_Close.PostId AND PH_Close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
LEFT JOIN CloseReasonTypes CR ON PH_Close.Comment = CAST(CR.Id AS TEXT)
WHERE
    PES.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
    AND PES.PostScore > 50
    AND PES.ViewCount > 10000
    AND PES.AnswerCount >= 3
    AND PES.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years')
    AND USV.Reputation >= 2000
    AND PES.RankByScoreWithinType <= 20
    AND (LOWER(PES.Title) LIKE '%sql%' OR LOWER(PES.Title) LIKE '%database%' OR LOWER(PPT.TagName) = 'postgresql')
    AND PES.Tags IS NOT NULL AND PES.Tags <> '$$'
    AND PES.LatestCommentText IS NOT NULL
    AND PES.AverageCommentScore > 1.0

UNION ALL

SELECT
    'HighQualityAnswer' AS RecordType,
    USV.UserId,
    USV.DisplayName,
    USV.Reputation,
    PES.PostId,
    PES.PostTypeId,
    PT.Name AS PostTypeName,
    PES.PostCreationDate,
    PES.PostScore,
    PES.ViewCount AS PostViewCount,
    NULL AS QuestionAnswerCount,
    PES.CommentCount AS PostCommentCount,
    PES.FavoriteCount AS PostFavoriteCount,
    NULL AS PostTitle,
    NULL AS PostTags,
    PES.StatusChangeDate,
    PES.LatestCommentText,
    PES.AverageCommentScore,
    NULL AS PrimaryTagName,
    NULL AS TagUseCount,
    COALESCE(CR.Name, 'N/A') AS CloseReason,
    CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - PES.PostCreationDate)) / 3600 / 24 AS INT) AS PostAgeInDays,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked')) AS LinkedPostCount,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.RelatedPostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked')) AS LinkedByPostCount,
    (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = PES.PostId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')) AS DuplicatePostCount,
    MD5(UPPER(COALESCE(USV.DisplayName, 'UNKNOWN') || COALESCE(PES.LatestCommentText, 'NO_COMMENT') || CAST(PES.PostCreationDate AS TEXT))) AS ContentHash
FROM UserStatsAndVotes USV
INNER JOIN PostEngagementSummary PES ON USV.UserId = PES.OwnerUserId
LEFT JOIN PostTypes PT ON PES.PostTypeId = PT.Id
LEFT JOIN PostHistory PH_Close ON PES.PostId = PH_Close.PostId AND PH_Close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
LEFT JOIN CloseReasonTypes CR ON PH_Close.Comment = CAST(CR.Id AS TEXT)
WHERE
    PES.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
    AND PES.PostScore > 75
    AND PES.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
    AND USV.Reputation >= 5000
    AND PES.RankByScoreWithinType <= 15
    AND USV.AnswersAcceptedCount > 10
    AND PES.CommentCount > 0
    AND PES.AverageCommentScore > 2.0
    AND EXISTS (
        SELECT 1 FROM Posts Q
        WHERE Q.Id = PES.ParentId
          AND Q.Tags IS NOT NULL
          AND (LOWER(Q.Tags) LIKE '%<java>%' OR LOWER(Q.Tags) LIKE '%<spring>%')
    )
ORDER BY
    Reputation DESC,
    PostScore DESC,
    PostCreationDate DESC
LIMIT 1000;