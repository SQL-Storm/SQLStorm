WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS TotalGivenUpVotes,
        U.DownVotes AS TotalGivenDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0) AS AvgAnswerScore,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate
    FROM Users AS U
    INNER JOIN Posts AS P ON U.Id = P.OwnerUserId
    WHERE U.CreationDate >= '2019-01-01'
      AND P.CreationDate BETWEEN U.CreationDate AND U.LastAccessDate
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5
),
PostClosureAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS QuestionOwnerId,
        P.CreationDate AS QuestionCreationDate,
        P.Title AS QuestionTitle,
        PH.CreationDate AS CloseHistoryDate,
        CR.Name AS CloseReasonName,
        CAST(SUBSTRING(PH.Comment FROM POSITION('=' IN PH.Comment) + 1 FOR CHAR_LENGTH(PH.Comment)) AS SMALLINT) AS CloseReasonId,
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate))) / 3600 AS HoursSincePreviousEditOrCreationToClose
    FROM Posts AS P
    INNER JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN CloseReasonTypes AS CR ON CAST(SUBSTRING(PH.Comment FROM POSITION('=' IN PH.Comment) + 1 FOR CHAR_LENGTH(PH.Comment)) AS SMALLINT) = CR.Id
    WHERE P.PostTypeId = 1
      AND PH.PostHistoryTypeId = 10
      AND PH.Comment LIKE 'CloseReasonId=%'
),
UserPostMetrics AS (
    SELECT
        UES.UserId,
        UES.UserName,
        UES.Reputation,
        UES.TotalPosts,
        UES.QuestionCount,
        UES.AnswerCount,
        UES.AvgQuestionScore,
        UES.AvgAnswerScore,
        UES.TotalGivenUpVotes,
        UES.TotalGivenDownVotes,
        SUM(CASE WHEN PCA.CloseReasonName = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateClosedCount,
        SUM(CASE WHEN PCA.CloseReasonName = 'Off-topic' THEN 1 ELSE 0 END) AS OffTopicClosedCount,
        COUNT(DISTINCT PCA.PostId) AS TotalClosedQuestions,
        COALESCE(AVG(PCA.HoursSincePreviousEditOrCreationToClose), 0) AS AvgHoursToFirstClose,
        (SELECT COALESCE(AVG(CHAR_LENGTH(C.Text)), 0)
         FROM Comments AS C
         WHERE C.UserId = UES.UserId
           AND C.CreationDate BETWEEN UES.EarliestPostDate AND UES.LatestPostDate
           AND C.Text IS NOT NULL AND CHAR_LENGTH(C.Text) > 5
        ) AS AvgCommentLengthByAuthor,
        COALESCE(
            (SELECT COUNT(DISTINCT CM.Id)
             FROM Comments AS CM
             INNER JOIN Posts AS P ON CM.PostId = P.Id
             WHERE P.OwnerUserId = UES.UserId AND CM.UserId IS NULL
            ), 0) AS AnonCommentsOnUserPosts
    FROM UserEngagementSummary AS UES
    LEFT JOIN PostClosureAnalysis AS PCA ON UES.UserId = PCA.QuestionOwnerId
    GROUP BY UES.UserId, UES.UserName, UES.Reputation, UES.TotalPosts, UES.QuestionCount, UES.AnswerCount, UES.AvgQuestionScore, UES.AvgAnswerScore,
             UES.EarliestPostDate, UES.LatestPostDate, UES.TotalGivenUpVotes, UES.TotalGivenDownVotes
),
DetailedBadgeAndTagMetrics AS (
    WITH TagCountsPerUser AS (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(LOWER(tag)) AS TagName,
            COUNT(P.Id) AS TagUsageCount
        FROM Posts AS P,
             LATERAL (
               SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR CHAR_LENGTH(P.Tags) - 2), '><')) AS tag
             ) AS t
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND CHAR_LENGTH(P.Tags) > 2
        GROUP BY P.OwnerUserId, TRIM(LOWER(tag))
    ),
    RankedTagCounts AS (
        SELECT
            UserId,
            TagName,
            TagUsageCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsageCount DESC, TagName ASC) AS rn
        FROM TagCountsPerUser
    )
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MAX(CASE WHEN RTC.rn = 1 THEN RTC.TagName ELSE NULL END) AS MostFrequentTag,
        MAX(CASE WHEN RTC.rn = 1 THEN RTC.TagUsageCount ELSE NULL END) AS MostFrequentTagCount
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN RankedTagCounts AS RTC ON U.Id = RTC.UserId
    GROUP BY U.Id
),
UserVoteAggregates AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersReceivedCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotesReceived
    FROM Posts AS P
    INNER JOIN Votes AS V ON P.Id = V.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
FinalUserRanking AS (
    SELECT
        UPM.UserId,
        UPM.UserName,
        UPM.Reputation,
        UPM.TotalPosts,
        UPM.QuestionCount,
        UPM.AnswerCount,
        UPM.AvgQuestionScore,
        UPM.AvgAnswerScore,
        UPM.DuplicateClosedCount,
        UPM.OffTopicClosedCount,
        UPM.TotalClosedQuestions,
        UPM.AvgHoursToFirstClose,
        UPM.AvgCommentLengthByAuthor,
        UPM.AnonCommentsOnUserPosts,
        DBATM.TotalBadges,
        DBATM.GoldBadges,
        DBATM.TagBasedBadges,
        DBATM.MostFrequentTag,
        DBATM.MostFrequentTagCount,
        UVA.TotalUpvotesReceived,
        UVA.TotalDownvotesReceived,
        UVA.AcceptedAnswersReceivedCount,
        UVA.FavoriteVotesReceived,
        (UPM.Reputation * 0.15 +
         UPM.AvgQuestionScore * 0.20 +
         UPM.AvgAnswerScore * 0.25 +
         (COALESCE(UVA.TotalUpvotesReceived, 0) - COALESCE(UVA.TotalDownvotesReceived, 0)) * 0.10 +
         COALESCE(DBATM.GoldBadges, 0) * 50 +
         UPM.TotalGivenUpVotes * 0.05 -
         UPM.TotalGivenDownVotes * 0.02 -
         (UPM.DuplicateClosedCount + UPM.OffTopicClosedCount) * 20
        ) AS UserImpactScore,
        DENSE_RANK() OVER (ORDER BY (UPM.Reputation * 0.15 + UPM.AvgQuestionScore * 0.20 + UPM.AvgAnswerScore * 0.25 + (COALESCE(UVA.TotalUpvotesReceived, 0) - COALESCE(UVA.TotalDownvotesReceived, 0)) * 0.10 + COALESCE(DBATM.GoldBadges, 0) * 50 + UPM.TotalGivenUpVotes * 0.05 - UPM.TotalGivenDownVotes * 0.02 - (UPM.DuplicateClosedCount + UPM.OffTopicClosedCount) * 20) DESC) AS OverallImpactRank
    FROM UserPostMetrics AS UPM
    LEFT JOIN DetailedBadgeAndTagMetrics AS DBATM ON UPM.UserId = DBATM.UserId
    LEFT JOIN UserVoteAggregates AS UVA ON UPM.UserId = UVA.UserId
),
UsersWithHighImpactOrSpecificInterests AS (
    SELECT
        FUR.*,
        'High Impact & Closed Posts' AS UserCategory
    FROM FinalUserRanking AS FUR
    WHERE FUR.OverallImpactRank <= 100
      AND FUR.TotalClosedQuestions > 0
      AND FUR.AvgHoursToFirstClose BETWEEN 0 AND 48
      AND FUR.MostFrequentTag IS NOT NULL AND FUR.MostFrequentTag NOT IN ('java', 'c#', 'python')
      AND FUR.AvgCommentLengthByAuthor >= 20
      AND FUR.TotalUpvotesReceived IS NOT NULL AND FUR.TotalUpvotesReceived > (COALESCE(FUR.TotalDownvotesReceived, 0) * 3)
),
UsersWithHighReputationAndActivity AS (
    SELECT
        FUR.*,
        'High Reputation & Activity' AS UserCategory
    FROM FinalUserRanking AS FUR
    WHERE FUR.Reputation > 10000
      AND COALESCE(FUR.GoldBadges, 0) >= 5
      AND FUR.QuestionCount >= 10 AND FUR.AnswerCount >= 30
      AND FUR.AnonCommentsOnUserPosts = 0
      AND FUR.UserImpactScore > 5000
)
SELECT
    A.UserId,
    A.UserName,
    A.Reputation,
    A.TotalPosts,
    A.QuestionCount,
    A.AnswerCount,
    A.DuplicateClosedCount,
    A.OffTopicClosedCount,
    A.TotalClosedQuestions,
    A.AvgHoursToFirstClose,
    A.AvgCommentLengthByAuthor,
    A.TotalBadges,
    A.GoldBadges,
    A.MostFrequentTag,
    A.MostFrequentTagCount,
    A.TotalUpvotesReceived,
    A.TotalDownvotesReceived,
    A.AcceptedAnswersReceivedCount,
    A.FavoriteVotesReceived,
    A.UserImpactScore,
    A.OverallImpactRank,
    A.UserCategory,
    CASE
        WHEN A.UserImpactScore > 15000 AND COALESCE(A.GoldBadges, 0) >= 10 THEN 'Elite Contributor'
        WHEN A.UserImpactScore > 10000 AND A.TotalClosedQuestions <= 1 THEN 'Trusted Expert'
        WHEN A.UserImpactScore > 5000 AND A.AvgCommentLengthByAuthor >= 50 THEN 'Engaged Communicator'
        ELSE 'Active Participant'
    END AS UserPersona,
    COALESCE(
        SUBSTRING(U.AboutMe FROM POSITION('<p>' IN U.AboutMe) + 3 FOR
            CASE
                WHEN POSITION('</p>' IN U.AboutMe) > POSITION('<p>' IN U.AboutMe) + 3
                THEN POSITION('</p>' IN U.AboutMe) - (POSITION('<p>' IN U.AboutMe) + 3)
                ELSE 0
            END
        ), 'No public "About Me" snippet available.') AS AboutMeFirstParagraphSnippet,
    U.Location,
    (U.WebsiteUrl IS NOT NULL) AS HasWebsite
FROM UsersWithHighImpactOrSpecificInterests AS A
INNER JOIN Users AS U ON A.UserId = U.Id
WHERE U.Location IS NOT NULL AND CHAR_LENGTH(TRIM(U.Location)) > 5
  AND (U.AboutMe LIKE '%developer%' OR U.AboutMe LIKE '%engineer%' OR U.WebsiteUrl IS NOT NULL)
  AND A.Reputation / NULLIF(A.TotalPosts, 0) > 50
UNION ALL
SELECT
    B.UserId,
    B.UserName,
    B.Reputation,
    B.TotalPosts,
    B.QuestionCount,
    B.AnswerCount,
    B.DuplicateClosedCount,
    B.OffTopicClosedCount,
    B.TotalClosedQuestions,
    B.AvgHoursToFirstClose,
    B.AvgCommentLengthByAuthor,
    B.TotalBadges,
    B.GoldBadges,
    B.MostFrequentTag,
    B.MostFrequentTagCount,
    B.TotalUpvotesReceived,
    B.TotalDownvotesReceived,
    B.AcceptedAnswersReceivedCount,
    B.FavoriteVotesReceived,
    B.UserImpactScore,
    B.OverallImpactRank,
    B.UserCategory,
    CASE
        WHEN B.UserImpactScore > 15000 AND COALESCE(B.GoldBadges, 0) >= 10 THEN 'Elite Contributor'
        WHEN B.UserImpactScore > 10000 AND B.TotalClosedQuestions <= 1 THEN 'Trusted Expert'
        WHEN B.UserImpactScore > 5000 AND B.AvgCommentLengthByAuthor >= 50 THEN 'Engaged Communicator'
        ELSE 'Active Participant'
    END AS UserPersona,
    COALESCE(
        SUBSTRING(U.AboutMe FROM POSITION('<p>' IN U.AboutMe) + 3 FOR
            CASE
                WHEN POSITION('</p>' IN U.AboutMe) > POSITION('<p>' IN U.AboutMe) + 3
                THEN POSITION('</p>' IN U.AboutMe) - (POSITION('<p>' IN U.AboutMe) + 3)
                ELSE 0
            END
        ), 'No public "About Me" snippet available.') AS AboutMeFirstParagraphSnippet,
    U.Location,
    (U.WebsiteUrl IS NOT NULL) AS HasWebsite
FROM UsersWithHighReputationAndActivity AS B
INNER JOIN Users AS U ON B.UserId = U.Id
WHERE U.Location IS NOT NULL AND U.Location LIKE '%United States%'
  AND B.TotalPosts > 100
  AND COALESCE(B.TotalBadges, 0) <> 0
  AND COALESCE(CAST(B.GoldBadges AS NUMERIC) / NULLIF(CAST(B.TotalBadges AS NUMERIC), 0), 0) > 0.05
ORDER BY UserImpactScore DESC, Reputation DESC
LIMIT 500;