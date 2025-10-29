-- {"query": "1861.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3480}
WITH UserSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS LastGoldBadgeDate,
        MIN(CASE WHEN B.Class = 3 THEN B.Date ELSE NULL END) AS FirstBronzeBadgeDate,
        ARRAY_AGG(DISTINCT B.Name ORDER BY B.Name) FILTER (WHERE B.TagBased = TRUE) AS TagBadgesList
    FROM
        Users U
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    WHERE
        U.Reputation > 500 AND U.Views > 100
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostActivityDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        P.ClosedDate,
        (P.ClosedDate IS NOT NULL) AS IsClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditorHistoryDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        (
            SELECT CR.Name
            FROM PostHistory PH_close
            JOIN CloseReasonTypes CR ON CAST(PH_close.Comment AS SMALLINT) = CR.Id
            WHERE PH_close.PostId = P.Id AND PH_close.PostHistoryTypeId = 10
            ORDER BY PH_close.CreationDate DESC
            LIMIT 1
        ) AS CloseReasonName,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.CreationDate DESC) AS PostRankByUserType,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId) AS OwnerAvgPostScore,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate,
        (EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400) AS DaysActivePost,
        CASE
            WHEN P.Score > 50 AND P.ViewCount > 1000 THEN 'HighlyEngaged'
            WHEN P.Score > 10 OR P.ViewCount > 500 THEN 'ModeratelyEngaged'
            ELSE 'LowEngagement'
        END AS EngagementSegment
    FROM
        Posts P
    INNER JOIN
        PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 16)
    WHERE
        P.CreationDate >= TIMESTAMP '2020-01-01' AND P.OwnerUserId IS NOT NULL AND P.Body IS NOT NULL AND CHAR_LENGTH(P.Body) > 50
        AND P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.ParentId,
        P.Title, P.Tags, P.ClosedDate, P.LastEditDate, P.LastActivityDate
),
CommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        SUM(C.Score) AS TotalCommentScoreOnPost,
        ARRAY_AGG(DISTINCT
            CASE
                WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%helpful%' THEN 'Positive'
                WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' THEN 'Negative'
                ELSE 'Neutral'
            END
            ORDER BY CASE
                WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%helpful%' THEN 'Positive'
                WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' THEN 'Negative'
                ELSE 'Neutral'
            END
        ) AS CommentSentimentCategories,
        MAX(C.CreationDate) AS LastCommentDateOnPost
    FROM
        Comments C
    WHERE
        C.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY C.PostId
),
QuestionTagBreakdown AS (
    SELECT
        PAD.PostId AS QuestionId,
        UNNEST(string_to_array(SUBSTRING(PAD.Tags FROM 2 FOR CHAR_LENGTH(PAD.Tags)-2), '><')) AS ParsedTag
    FROM
        PostActivityDetails PAD
    WHERE
        PAD.PostTypeId = 1 AND PAD.Tags IS NOT NULL AND CHAR_LENGTH(PAD.Tags) > 2
),
AnswerLinkAnalysis AS (
    SELECT
        PL.PostId AS AnswerId,
        PL.RelatedPostId AS QuestionLinkedId,
        COUNT(PL.Id) AS OutgoingLinks,
        SUM(CASE WHEN LT.Name = 'Linked' THEN 1 ELSE 0 END) AS DirectLinks,
        SUM(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM
        PostLinks PL
    JOIN
        LinkTypes LT ON PL.LinkTypeId = LT.Id
    WHERE
        PL.CreationDate >= TIMESTAMP '2020-01-01'
        AND PL.PostId IN (SELECT PostId FROM PostActivityDetails WHERE PostTypeId = 2)
    GROUP BY
        PL.PostId, PL.RelatedPostId
)
SELECT
    US.UserId,
    US.DisplayName AS UserDisplayName,
    US.Reputation,
    US.TotalBadges,
    US.LastGoldBadgeDate,
    PAD.PostId,
    PAD.PostTypeName,
    PAD.Title AS PostTitle,
    PAD.PostCreationDate,
    PAD.Score AS PostScore,
    PAD.ViewCount,
    PAD.UpVoteCount,
    PAD.DownVoteCount,
    PAD.TotalHistoryEvents,
    PAD.CloseReasonName,
    PAD.EngagementSegment,
    CS.TotalCommentsOnPost,
    CS.TotalCommentScoreOnPost,
    CS.CommentSentimentCategories,
    T.TagName,
    T.Count AS TagGlobalCount,
    CAST(NULL AS BIGINT) AS OutgoingLinks,
    CAST(NULL AS BIGINT) AS DirectLinks,
    CAST(NULL AS BIGINT) AS DuplicateLinks,
    PAD.OwnerAvgPostScore,
    NTILE(100) OVER (ORDER BY PAD.Score DESC, PAD.ViewCount DESC) AS PostScoreViewPercentile,
    PAD.PreviousPostCreationDate AS TimeOfPreviousPostBySameUser,
    (PAD.PostCreationDate - PAD.PreviousPostCreationDate) AS TimeSinceLastPostInterval,
    AGE(US.LastAccessDate, US.UserCreationDate) AS UserAccountAge,
    COALESCE(PAD.FavoriteCount, 0) AS ActualFavoriteCount,
    'Question' AS PostCategoryFlag,
    AVG(PAD.Score) OVER (PARTITION BY T.TagName) AS AvgScoreForTag,
    SUM(CASE WHEN PAD.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY US.UserId) AS TotalQuestionsByUser,
    SUM(CASE WHEN PAD.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY US.UserId) AS TotalAnswersByUser,
    (
        SELECT COUNT(DISTINCT C_sub.Id)
        FROM Comments C_sub
        WHERE C_sub.UserId = US.UserId AND C_sub.CreationDate BETWEEN US.UserCreationDate AND US.LastAccessDate
        AND LOWER(C_sub.Text) LIKE '%question%'
    ) AS UserCommentedOnQuestions,
    'HighViewQuestionAnalysis' AS AnalysisType
FROM
    UserSummary US
INNER JOIN
    PostActivityDetails PAD ON US.UserId = PAD.OwnerUserId
LEFT JOIN
    CommentSummary CS ON PAD.PostId = CS.PostId
LEFT JOIN
    QuestionTagBreakdown QTB ON PAD.PostId = QTB.QuestionId
LEFT JOIN
    Tags T ON QTB.ParsedTag = T.TagName
WHERE
    PAD.PostTypeId = 1
    AND PAD.ViewCount > 5000
    AND PAD.Score > 100
    AND US.Reputation > (SELECT AVG(Reputation) * 1.5 FROM Users WHERE CreationDate >= TIMESTAMP '2019-01-01')
    AND T.TagName IN ('sql', 'database', 'performance', 'indexing', 'optimization')
    AND US.DisplayName IS NOT NULL AND US.DisplayName <> ''
    AND (PAD.ClosedDate IS NULL OR PAD.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'))
    AND PAD.PostRankByUserType <= 3
    AND US.TagBadgesList IS NOT NULL AND CARDINALITY(US.TagBadgesList) > 0
UNION ALL
SELECT
    US.UserId,
    US.DisplayName AS UserDisplayName,
    US.Reputation,
    US.TotalBadges,
    US.LastGoldBadgeDate,
    PAD.PostId,
    PAD.PostTypeName,
    PAD.Title AS PostTitle,
    PAD.PostCreationDate,
    PAD.Score AS PostScore,
    PAD.ViewCount,
    PAD.UpVoteCount,
    PAD.DownVoteCount,
    PAD.TotalHistoryEvents,
    PAD.CloseReasonName,
    PAD.EngagementSegment,
    CS.TotalCommentsOnPost,
    CS.TotalCommentScoreOnPost,
    CS.CommentSentimentCategories,
    CAST(NULL AS VARCHAR(35)) AS TagName,
    CAST(NULL AS INTEGER) AS TagGlobalCount,
    ALA.OutgoingLinks,
    ALA.DirectLinks,
    ALA.DuplicateLinks,
    PAD.OwnerAvgPostScore,
    NTILE(100) OVER (ORDER BY PAD.Score DESC) AS PostScoreViewPercentile,
    PAD.PreviousPostCreationDate AS TimeOfPreviousPostBySameUser,
    (PAD.PostCreationDate - PAD.PreviousPostCreationDate) AS TimeSinceLastPostInterval,
    AGE(US.LastAccessDate, US.UserCreationDate) AS UserAccountAge,
    COALESCE(PAD.FavoriteCount, 0) AS ActualFavoriteCount,
    'AcceptedAnswer' AS PostCategoryFlag,
    CAST(NULL AS NUMERIC) AS AvgScoreForTag,
    SUM(CASE WHEN PAD.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY US.UserId) AS TotalQuestionsByUser,
    SUM(CASE WHEN PAD.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY US.UserId) AS TotalAnswersByUser,
    (
        SELECT COUNT(DISTINCT C_sub.Id)
        FROM Comments C_sub
        WHERE C_sub.UserId = US.UserId AND C_sub.CreationDate BETWEEN US.UserCreationDate AND US.LastAccessDate
        AND LOWER(C_sub.Text) LIKE '%answer%'
    ) AS UserCommentedOnQuestions,
    'AcceptedAnswerAnalysis' AS AnalysisType
FROM
    UserSummary US
INNER JOIN
    PostActivityDetails PAD ON US.UserId = PAD.OwnerUserId
LEFT JOIN
    CommentSummary CS ON PAD.PostId = CS.PostId
LEFT JOIN
    AnswerLinkAnalysis ALA ON PAD.PostId = ALA.AnswerId
WHERE
    PAD.PostTypeId = 2
    AND PAD.Score > 75
    AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = PAD.ParentId AND Q.AcceptedAnswerId = PAD.PostId)
    AND US.Reputation > (SELECT AVG(Reputation) * 1.2 FROM Users WHERE CreationDate >= TIMESTAMP '2019-01-01')
    AND US.DisplayName IS NOT NULL AND US.DisplayName <> ''
    AND PAD.PostRankByUserType <= 2
    AND (LOWER(PAD.Title) LIKE '%best practice%' OR LOWER(PAD.Title) LIKE '%optimization%' OR LOWER(PAD.Title) LIKE '%solution%')
ORDER BY
    Reputation DESC, PostScore DESC, PostCreationDate DESC;