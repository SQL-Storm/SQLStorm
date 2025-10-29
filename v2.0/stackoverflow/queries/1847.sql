WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END), 0) AS TotalBountyCreated,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.PostId END) AS PostsUpVotedByUser,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.PostId END) AS PostsDownVotedByUser,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score END) AS AveragePostScore
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    WHERE
        U.CreationDate >= DATE '2019-01-01'
        AND U.Reputation > 500
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionMetaAnalysis AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Title,
        Q.Tags,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.AnswerCount,
        Q.FavoriteCount,
        string_to_array(substring(Q.Tags FROM 2 FOR (length(Q.Tags) - 2)), '><') AS TagArray,
        row_number() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate DESC, Q.Score DESC) AS rn_latest_question,
        AVG(Q.Score) OVER (PARTITION BY EXTRACT(YEAR FROM Q.CreationDate)) AS YearlyAvgQuestionScore,
        COUNT(DISTINCT C.Id) AS CommentCountOnQuestion,
        CASE WHEN Q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        (POSITION('performance' IN LOWER(Q.Body)) > 0 OR POSITION('optimization' IN LOWER(Q.Body)) > 0) AS IsPerformanceRelatedBody,
        LAG(Q.CreationDate, 1, TIMESTAMP '1900-01-01') OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PreviousQuestionDate
    FROM
        Posts Q
    LEFT JOIN
        Comments C ON Q.Id = C.PostId
    WHERE
        Q.PostTypeId = 1
        AND Q.CreationDate >= DATE '2019-01-01'
    GROUP BY
        Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Title, Q.Tags, Q.ViewCount, Q.Score, Q.AnswerCount, Q.FavoriteCount, Q.Body, Q.AcceptedAnswerId
),
PostModerationHistory AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PH.UserId AS HistoryUserId,
        PH.Comment AS HistoryComment,
        LEAD(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextHistoryEventType,
        LAG(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryEventType,
        COALESCE(CRT.Name, 'N/A') AS CloseReasonTypeName
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CRT ON (PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' AND CAST(PH.Comment AS smallint) = CRT.Id)
    WHERE
        PH.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20, 35, 36)
),
ClosedReopenedQuestionOwners AS (
    SELECT DISTINCT
        QMA.OwnerUserId AS UserId
    FROM
        QuestionMetaAnalysis QMA
    JOIN
        PostModerationHistory PMH_Closed ON QMA.QuestionId = PMH_Closed.PostId AND PMH_Closed.PostHistoryTypeId = 10
    JOIN
        PostModerationHistory PMH_Reopened ON QMA.QuestionId = PMH_Reopened.PostId AND PMH_Reopened.PostHistoryTypeId = 11
    WHERE
        PMH_Reopened.HistoryDate > PMH_Closed.HistoryDate
),
TopTagsByUsers AS (
    SELECT
        QMA.OwnerUserId AS UserId,
        T.TagName,
        COUNT(DISTINCT QMA.QuestionId) AS QuestionsWithTag,
        DENSE_RANK() OVER (PARTITION BY QMA.OwnerUserId ORDER BY COUNT(DISTINCT QMA.QuestionId) DESC, T.TagName) AS TagRank
    FROM
        QuestionMetaAnalysis QMA,
        UNNEST(QMA.TagArray) AS T(TagName)
    WHERE
        length(T.TagName) > 2 AND T.TagName NOT LIKE '%-tag'
    GROUP BY
        QMA.OwnerUserId, T.TagName
    HAVING
        COUNT(DISTINCT QMA.QuestionId) >= 2
),
BadgeAchievements AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadgesCount
    FROM
        Badges B
    GROUP BY
        B.UserId
),
UserQuestionDates AS (
    SELECT
        OwnerUserId AS UserId,
        MIN(QuestionCreationDate) AS FirstQuestionDate,
        MAX(QuestionCreationDate) AS LastQuestionDate
    FROM
        QuestionMetaAnalysis
    GROUP BY
        OwnerUserId
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.TotalQuestions,
    UES.TotalAnswers,
    UES.TotalPostScore,
    UES.TotalBountyCreated,
    UES.PostsUpVotedByUser,
    UES.PostsDownVotedByUser,
    QMA_latest.Title AS LatestQuestionTitle,
    QMA_latest.QuestionScore AS LatestQuestionScore,
    QMA_latest.CommentCountOnQuestion AS LatestQuestionCommentCount,
    array_to_string(QMA_latest.TagArray, ' / ') AS LatestQuestionTags,
    QMA_latest.YearlyAvgQuestionScore,
    QMA_latest.HasAcceptedAnswer AS LatestQuestionHasAcceptedAnswer,
    QMA_latest.IsPerformanceRelatedBody,
    BA.TotalBadges,
    BA.GoldBadges,
    BA.SilverBadges,
    BA.BronzeBadges,
    BA.FirstBadgeDate,
    BA.LastBadgeDate,
    UQD.FirstQuestionDate,
    UQD.LastQuestionDate,
    EXTRACT(DAY FROM (QMA_latest.QuestionCreationDate - QMA_latest.PreviousQuestionDate)) AS DaysSincePreviousQuestion,
    COALESCE(SQ_CommunityOwnedPosts.TotalCommunityOwnedPosts, 0) AS TotalCommunityOwnedPosts,
    CASE
        WHEN UES.Reputation > 75000 AND COALESCE(BA.GoldBadges,0) >= 10 THEN 'Elite Guru'
        WHEN UES.Reputation > 25000 AND UES.TotalAnswers > UES.TotalQuestions * 1.5 AND COALESCE(UES.AveragePostScore,0) > 5 THEN 'Pro Answerer'
        WHEN UES.TotalQuestions > 100 AND QMA_latest.IsPerformanceRelatedBody AND UES.TotalPostScore > 500 THEN 'Topic Lead Questioner'
        WHEN COALESCE(UES.TotalPosts,0) >= 0 AND COALESCE(UES.UserUpVotesGiven,0) > 1000 AND COALESCE(UES.TotalPosts,0) >= 0 AND COALESCE(BA.TotalBadges,0) >= 50 THEN 'Engaged Veteran'
        WHEN COALESCE(UES.TotalQuestions,0) + COALESCE(UES.TotalAnswers,0) < 10 AND UES.Reputation < 1000 THEN 'Novice Contributor'
        ELSE 'Active Participant'
    END AS UserEngagementTier,
    NTILE(10) OVER (ORDER BY UES.Reputation DESC, UES.TotalPostScore DESC) AS ReputationDecile,
    EXISTS (
        SELECT 1
        FROM ClosedReopenedQuestionOwners CRQO
        WHERE CRQO.UserId = UES.UserId
    ) AS HasClosedReopenedQuestion,
    COALESCE(
        (SELECT TTBU.TagName
         FROM TopTagsByUsers TTBU
         WHERE TTBU.UserId = UES.UserId AND TTBU.TagRank = 1
         LIMIT 1
        ), 'No Top Tag'
    ) AS UsersTopTag,
    (
        SELECT AVG(P_linked.Score)
        FROM Posts P_linked
        JOIN PostLinks PL ON P_linked.Id = PL.RelatedPostId
        WHERE PL.PostId = QMA_latest.QuestionId AND PL.LinkTypeId = 3
    ) AS AvgScoreOfDuplicatingPosts,
    (
        SELECT COUNT(DISTINCT C_others.PostId)
        FROM Comments C_others
        JOIN Posts P_others ON C_others.PostId = P_others.Id
        WHERE C_others.UserId = UES.UserId AND (P_others.OwnerUserId IS NULL OR P_others.OwnerUserId IS DISTINCT FROM UES.UserId)
    ) AS CommentsOnOtherUsersPosts,
    (
        SELECT PMH_Closed.CloseReasonTypeName
        FROM PostModerationHistory PMH_Closed
        WHERE PMH_Closed.PostId = QMA_latest.QuestionId AND PMH_Closed.PostHistoryTypeId = 10
        ORDER BY PMH_Closed.HistoryDate DESC
        LIMIT 1
    ) AS LatestCloseReasonForLatestQuestion
FROM
    UserEngagementSummary UES
LEFT JOIN
    BadgeAchievements BA ON UES.UserId = BA.UserId
LEFT JOIN
    QuestionMetaAnalysis QMA_latest ON UES.UserId = QMA_latest.OwnerUserId AND QMA_latest.rn_latest_question = 1
LEFT JOIN
    UserQuestionDates UQD ON UES.UserId = UQD.UserId
LEFT JOIN
    (SELECT P.OwnerUserId, COUNT(P.Id) AS TotalCommunityOwnedPosts
     FROM Posts P
     WHERE P.CommunityOwnedDate IS NOT NULL AND P.OwnerUserId IS NOT NULL
     GROUP BY P.OwnerUserId) AS SQ_CommunityOwnedPosts
     ON UES.UserId = SQ_CommunityOwnedPosts.OwnerUserId
WHERE
    UES.TotalPosts > 5
    AND (UES.TotalQuestions > 2 OR UES.TotalAnswers > 5)
    AND UES.DisplayName IS NOT NULL
    AND UES.DisplayName NOT ILIKE '%bot%'
    AND (COALESCE(QMA_latest.QuestionScore, -999999) > 3 OR COALESCE(BA.GoldBadges, 0) > 0)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_DeletedByOwner
        WHERE PH_DeletedByOwner.UserId = UES.UserId
          AND PH_DeletedByOwner.PostHistoryTypeId = 12
          AND PH_DeletedByOwner.CreationDate > UES.UserCreationDate
          AND PH_DeletedByOwner.PostId IN (SELECT Q.Id FROM Posts Q WHERE Q.OwnerUserId = UES.UserId)
    )
ORDER BY
    ReputationDecile, UES.Reputation DESC
LIMIT 50000;