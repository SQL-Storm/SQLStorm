WITH UserPostCommentCounts AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(COUNT(DISTINCT P.Id) FILTER (WHERE P.OwnerUserId IS NOT NULL), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT C.Id) FILTER (WHERE C.UserId IS NOT NULL), 0) AS TotalCommentsMade
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalRevisions,
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate_Significant,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN PH.CreationDate ELSE NULL END) AS LastCloseReopenDate
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY PH.PostId
),
QuestionDetailedMetrics AS (
    SELECT
        Q.Id AS PostId,
        Q.OwnerUserId,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.FavoriteCount,
        Q.AnswerCount,
        CASE
            WHEN Q.Tags IS NULL OR Q.Tags = '' THEN 0
            ELSE (LENGTH(Q.Tags) - LENGTH(REPLACE(Q.Tags, '><', '')) + 1)
        END AS TagCount,
        CASE
            WHEN Q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN Q.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END AS Status,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts AS Q
    LEFT JOIN PostLinks AS PL ON Q.Id = PL.PostId
    LEFT JOIN Votes AS V ON Q.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.Score, Q.ViewCount, Q.FavoriteCount, Q.AnswerCount, Q.Tags, Q.ClosedDate, Q.CommunityOwnedDate
),
AnswerDetailedMetrics AS (
    SELECT
        A.Id AS PostId,
        A.OwnerUserId,
        A.Score AS AnswerScore,
        A.ParentId AS QuestionId,
        CASE WHEN A.Id = Q.AcceptedAnswerId THEN TRUE ELSE FALSE END AS IsAcceptedAnswer,
        COALESCE(Q.ViewCount, 0) AS ParentQuestionViewCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts AS A
    LEFT JOIN Posts AS Q ON A.ParentId = Q.Id
    LEFT JOIN Votes AS V ON A.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    WHERE A.PostTypeId = 2
    GROUP BY A.Id, A.OwnerUserId, A.Score, A.ParentId, Q.AcceptedAnswerId, Q.ViewCount
),
AllPostAggregatedMetrics AS (
    SELECT
        PostId,
        OwnerUserId,
        'Question' AS PostType,
        QuestionScore AS Score,
        ViewCount,
        FavoriteCount,
        AnswerCount AS RelatedPostsCount,
        TagCount,
        Status,
        LinkedPostsCount,
        DuplicatePostsCount,
        UpvoteCount,
        DownvoteCount,
        CAST(NULL AS BOOLEAN) AS IsAccepted,
        CAST(NULL AS INTEGER) AS ParentPostViewCount
    FROM QuestionDetailedMetrics
    UNION ALL
    SELECT
        PostId,
        OwnerUserId,
        'Answer' AS PostType,
        AnswerScore AS Score,
        NULL AS ViewCount,
        NULL AS FavoriteCount,
        NULL AS RelatedPostsCount,
        NULL AS TagCount,
        NULL AS Status,
        NULL AS LinkedPostsCount,
        NULL AS DuplicatePostsCount,
        UpvoteCount,
        DownvoteCount,
        IsAcceptedAnswer AS IsAccepted,
        ParentQuestionViewCount AS ParentPostViewCount
    FROM AnswerDetailedMetrics
),
UserOverallPerformance AS (
    SELECT
        UPC.UserId,
        UPC.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        UPC.TotalPosts,
        UPC.TotalQuestions,
        UPC.TotalAnswers,
        UPC.TotalCommentsMade,
        COALESCE(SUM(APAM.Score), 0) AS TotalPostScore,
        COALESCE(SUM(APAM.FavoriteCount), 0) AS TotalFavoriteCount,
        COALESCE(SUM(APAM.ViewCount), 0) AS TotalQuestionViews,
        COALESCE(AVG(APAM.Score) FILTER (WHERE APAM.PostType = 'Question'), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(APAM.Score) FILTER (WHERE APAM.PostType = 'Answer'), 0.0) AS AvgAnswerScore,
        COALESCE(SUM(APAM.UpvoteCount), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(APAM.DownvoteCount), 0) AS TotalDownvotesReceived,
        COALESCE(COUNT(DISTINCT PEA.PostId), 0) AS PostsWithHistory,
        COALESCE(SUM(PEA.TotalRevisions), 0) AS TotalPostRevisions,
        COALESCE(SUM(CASE WHEN APAM.PostType = 'Question' AND APAM.Status = 'Closed' THEN 1 ELSE 0 END), 0) AS TotalClosedQuestions,
        RANK() OVER (ORDER BY COALESCE(SUM(APAM.Score), 0) DESC, UPC.TotalPosts DESC) AS RankByOverallScore,
        NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
        (CAST(COALESCE(SUM(APAM.UpvoteCount) + SUM(APAM.DownvoteCount) + UPC.TotalCommentsMade * 2 + SUM(APAM.FavoriteCount) * 3, 0) AS DECIMAL)
         / NULLIF((COALESCE(UPC.TotalPosts, 0) + COALESCE(UPC.TotalCommentsMade, 0)), 0)) AS EngagementRatio,
        MAX(PEA.LastCloseReopenDate) AS LatestCloseOrReopenActivity
    FROM UserPostCommentCounts AS UPC
    INNER JOIN Users AS U ON UPC.UserId = U.Id
    LEFT JOIN AllPostAggregatedMetrics AS APAM ON UPC.UserId = APAM.OwnerUserId
    LEFT JOIN PostEditActivity AS PEA ON APAM.PostId = PEA.PostId
    GROUP BY UPC.UserId, UPC.DisplayName, U.Reputation, U.CreationDate, UPC.TotalPosts, UPC.TotalQuestions, UPC.TotalAnswers, UPC.TotalCommentsMade
),
UserBadgeTimeline AS (
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date ASC) AS Rn,
        LAG(B.Date, 1, B.Date) OVER (PARTITION BY B.UserId ORDER BY B.Date ASC) AS PreviousBadgeDate,
        LEAD(B.Date, 1, B.Date) OVER (PARTITION BY B.UserId ORDER BY B.Date ASC) AS NextBadgeDate
    FROM Badges AS B
)
SELECT
    UOP.UserId,
    UOP.DisplayName,
    UOP.Reputation,
    UOP.UserCreationDate,
    UOP.TotalPosts,
    UOP.TotalQuestions,
    UOP.TotalAnswers,
    UOP.TotalCommentsMade,
    UOP.TotalPostScore,
    UOP.AvgQuestionScore,
    UOP.AvgAnswerScore,
    UOP.TotalUpvotesReceived,
    UOP.TotalDownvotesReceived,
    UOP.PostsWithHistory,
    UOP.TotalPostRevisions,
    UOP.TotalClosedQuestions,
    UOP.RankByOverallScore,
    UOP.ReputationDecile,
    UOP.EngagementRatio,
    UOP.LatestCloseOrReopenActivity,
    COALESCE(U.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
    COALESCE(U.Location, 'Unknown') AS UserLocation,
    (SELECT UBT.BadgeName FROM UserBadgeTimeline AS UBT WHERE UBT.UserId = UOP.UserId AND UBT.Rn = 1) AS FirstBadgeName,
    (SELECT UBT.BadgeDate FROM UserBadgeTimeline AS UBT WHERE UBT.UserId = UOP.UserId AND UBT.Rn = 1) AS FirstBadgeDate,
    (
        SELECT
            T.TagName
        FROM Posts AS P_tags,
             UNNEST(string_to_array(substring(P_tags.Tags FROM 2 FOR (length(P_tags.Tags)-2)), '><')) AS Tag_name_array
        JOIN Tags AS T ON Tag_name_array = T.TagName
        WHERE P_tags.OwnerUserId = UOP.UserId
          AND P_tags.PostTypeId = 1
          AND P_tags.Tags IS NOT NULL
        GROUP BY T.TagName
        ORDER BY COUNT(P_tags.Id) DESC, SUM(P_tags.Score) DESC
        LIMIT 1
    ) AS TopContributingTag,
    (
        SELECT
            P_recent.Title
        FROM Posts AS P_recent
        WHERE P_recent.OwnerUserId = UOP.UserId AND P_recent.PostTypeId = 1
        ORDER BY P_recent.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionTitle,
    CASE
        WHEN UOP.TotalQuestions > 0 AND UOP.AvgQuestionScore > 10 THEN 'High-Impact Questioner'
        WHEN UOP.TotalAnswers > 0 AND UOP.AvgAnswerScore > 5 AND UOP.TotalPosts > UOP.TotalQuestions THEN 'Valuable Answerer'
        WHEN UOP.TotalPosts = 0 AND UOP.TotalCommentsMade > 0 THEN 'Commenter Only'
        WHEN UOP.TotalPosts > 0 AND UOP.TotalCommentsMade = 0 THEN 'Content Creator (No Comments)'
        ELSE 'General Contributor'
    END AS UserCategory,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - UOP.UserCreationDate)) / (60 * 60 * 24 * 365.25) AS YearsActive
FROM UserOverallPerformance AS UOP
LEFT JOIN Users AS U ON UOP.UserId = U.Id
WHERE UOP.Reputation > 100 AND UOP.TotalPosts > 0
ORDER BY UOP.Reputation DESC, UOP.EngagementRatio DESC
LIMIT 1000;