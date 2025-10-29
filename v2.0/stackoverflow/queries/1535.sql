-- {"query": "1535.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2984}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(C.Id) AS TotalComments,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedPosts,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedPosts,
        COALESCE(SUM(CASE WHEN V_User.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V_User.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    LEFT JOIN Votes V_User ON U.Id = V_User.UserId AND V_User.VoteTypeId IN (2, 3)
    GROUP BY U.Id
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
        MAX(CASE
                WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '101%' THEN 'Duplicate'
                WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '102%' THEN 'Off-topic'
                WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '103%' THEN 'Needs details'
                WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '104%' THEN 'Needs more focus'
                WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '105%' THEN 'Opinion-based'
                ELSE NULL
            END) AS LastCloseReasonCategory
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    GROUP BY PH.PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
TopQuestionTagsByUser AS (
    SELECT
        qta.OwnerUserId AS UserId,
        qta.TagName,
        COUNT(*) AS TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY qta.OwnerUserId ORDER BY COUNT(*) DESC, qta.TagName) AS TagRank
    FROM (
        SELECT
            P.OwnerUserId,
            TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
        FROM Posts P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    ) AS qta
    GROUP BY qta.OwnerUserId, qta.TagName
),
ModeratorActivitySummary AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS ModeratorActionsCount,
        MAX(PH.CreationDate) AS LatestModeratorActionDate,
        MIN(PH.CreationDate) AS FirstModeratorActionDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (14, 15, 19, 20)
    GROUP BY PH.UserId
),
UserQuestionStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        UAS.TotalPosts,
        UAS.TotalQuestions,
        UAS.TotalAnswers,
        UAS.TotalComments,
        UAS.TotalUpvotesReceivedPosts,
        UAS.TotalDownvotesReceivedPosts,
        UBS.TotalBadges,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        MAS.ModeratorActionsCount,
        MAS.LatestModeratorActionDate,
        MAS.FirstModeratorActionDate,
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        Q.LastEditDate AS QuestionLastEditDate,
        Q.Tags,
        Q.AcceptedAnswerId,
        Q.ClosedDate,
        PHD.EditCount AS QuestionEditCount,
        PHD.ReopenCount AS QuestionReopenCount,
        PHD.CloseCount AS QuestionCloseCount,
        PHD.LastCloseReasonCategory,
        TQT.TagName AS TopUsedQuestionTagName,
        TQT.TagUsageCount AS TopUsedTagCount,
        COALESCE(SUBSTRING(U.AboutMe, 1, 150), 'No description available for user.') AS AboutMeSnippet,
        COALESCE(U.Location, 'Unknown') || ' | ' || COALESCE(U.WebsiteUrl, 'No website') AS UserContactInfo,
        (CAST(
            (COALESCE(Q.Score, 0) + COALESCE(Q.FavoriteCount, 0) * 5 + COALESCE(Q.AnswerCount, 0) * 3 + COALESCE(Q.CommentCount, 0) * 0.5)
            AS DECIMAL(18,2)
        ) / NULLIF(COALESCE(Q.ViewCount, 0) + 1, 0)) AS QuestionEngagementRatio,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionRankByScore,
        AVG(Q.Score) OVER (PARTITION BY U.Id) AS AvgScoreForUsersQuestions,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile
    FROM Users U
    LEFT JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
    LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
    LEFT JOIN ModeratorActivitySummary MAS ON U.Id = MAS.UserId
    JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN PostHistoryDetails PHD ON Q.Id = PHD.PostId
    LEFT JOIN TopQuestionTagsByUser TQT ON U.Id = TQT.UserId AND TQT.TagRank = 1
    WHERE U.Reputation > 1000
      AND Q.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 year')
      AND Q.Score >= 5
      AND (U.AboutMe IS NOT NULL OR U.Location IS NOT NULL)
      AND NOT EXISTS (
          SELECT 1
          FROM Badges B_Inner
          WHERE B_Inner.UserId = U.Id
            AND B_Inner.Name LIKE '%Testing%'
      )
),
RelatedPostsAgg AS (
    SELECT
        PL.PostId,
        STRING_AGG(CAST(PL.RelatedPostId AS VARCHAR) || ' (' || LT.Name || ')', '; ' ORDER BY CAST(PL.RelatedPostId AS VARCHAR) || ' (' || LT.Name || ')') AS RelatedPostInfo
    FROM PostLinks PL
    JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    GROUP BY PL.PostId
),
LatestCommentDetails AS (
    SELECT
        C.PostId,
        C.Text AS LatestCommentText,
        C.CreationDate AS LatestCommentDate,
        ROW_NUMBER() OVER (PARTITION BY C.PostId ORDER BY C.CreationDate DESC) AS rn
    FROM Comments C
)
SELECT
    UQS.UserId,
    UQS.DisplayName,
    UQS.Reputation,
    UQS.UserViews,
    UQS.UserUpVotesGiven,
    UQS.UserDownVotesGiven,
    UQS.UserCreationDate,
    UQS.LastAccessDate,
    UQS.TotalPosts,
    UQS.TotalQuestions,
    UQS.TotalAnswers,
    UQS.TotalComments,
    UQS.TotalUpvotesReceivedPosts,
    UQS.TotalDownvotesReceivedPosts,
    UQS.TotalBadges,
    UQS.GoldBadges,
    UQS.SilverBadges,
    UQS.BronzeBadges,
    UQS.ModeratorActionsCount,
    UQS.LatestModeratorActionDate,
    UQS.FirstModeratorActionDate,
    UQS.QuestionId,
    UQS.QuestionTitle,
    UQS.QuestionScore,
    UQS.QuestionViewCount,
    UQS.QuestionAnswerCount,
    UQS.QuestionCommentCount,
    UQS.QuestionFavoriteCount,
    UQS.QuestionCreationDate,
    UQS.QuestionLastActivityDate,
    UQS.QuestionLastEditDate,
    UQS.Tags,
    UQS.AcceptedAnswerId,
    AA.Score AS AcceptedAnswerScore,
    COALESCE(AA_Owner.DisplayName, 'N/A') AS AcceptedAnswerOwnerDisplayName,
    AA_Owner.Reputation AS AcceptedAnswerOwnerReputation,
    UQS.ClosedDate,
    UQS.QuestionEditCount,
    UQS.QuestionReopenCount AS ReopenCount,
    UQS.QuestionCloseCount AS CloseCount,
    UQS.LastCloseReasonCategory,
    UQS.TopUsedQuestionTagName,
    UQS.TopUsedTagCount,
    UQS.AboutMeSnippet,
    UQS.UserContactInfo,
    UQS.QuestionEngagementRatio,
    UQS.UserQuestionRankByScore,
    UQS.AvgScoreForUsersQuestions,
    UQS.ReputationQuintile,
    RPA.RelatedPostInfo,
    LCD.LatestCommentText,
    LCD.LatestCommentDate,
    (SELECT AVG(A_Inner.Score)
     FROM Posts A_Inner
     WHERE A_Inner.ParentId = UQS.QuestionId AND A_Inner.PostTypeId = 2) AS AverageAnswerScoreForQuestion,
    CASE
        WHEN UQS.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN UQS.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswered'
        WHEN UQS.QuestionAnswerCount > 0 THEN 'HasAnswers'
        ELSE 'Open'
    END AS DetailedQuestionStatus,
    EXTRACT(EPOCH FROM ((CAST('2024-10-01 12:34:56' AS TIMESTAMP) - UQS.QuestionCreationDate))) / (3600 * 24) AS QuestionAgeDays,
    (
        EXISTS (SELECT 1 FROM Users U_hr WHERE U_hr.Id = UQS.UserId AND U_hr.Reputation > 5000 AND U_hr.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '10 year'))
        AND
        EXISTS (SELECT 1 FROM Badges B_gb WHERE B_gb.UserId = UQS.UserId AND B_gb.Class = 1 AND B_gb.Date > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 year'))
    ) AS IsHighReputationGoldBadgeUser
FROM UserQuestionStats UQS
LEFT JOIN Posts AA ON UQS.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2
LEFT JOIN Users AA_Owner ON AA.OwnerUserId = AA_Owner.Id
LEFT JOIN RelatedPostsAgg RPA ON UQS.QuestionId = RPA.PostId
LEFT JOIN LatestCommentDetails LCD ON UQS.QuestionId = LCD.PostId AND LCD.rn = 1
WHERE UQS.ReputationQuintile = 1
  AND UQS.QuestionEngagementRatio > 0.5
ORDER BY UQS.Reputation DESC, UQS.QuestionScore DESC, UQS.QuestionCreationDate DESC
LIMIT 1000;