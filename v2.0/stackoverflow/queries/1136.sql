-- {"query": "1136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3815}
WITH UserPostVoteSummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        COALESCE(SUM(CASE WHEN V_Received.VoteTypeId = 2 AND P.Id IS NOT NULL THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V_Received.VoteTypeId = 3 AND P.Id IS NOT NULL THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Votes V_Received ON P.Id = V_Received.PostId AND V_Received.VoteTypeId IN (2, 3)
    LEFT JOIN
        Votes V_Given ON U.Id = V_Given.UserId AND V_Given.VoteTypeId IN (2, 3)
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
PostDetailedAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        CASE
            WHEN LOWER(P.Body) LIKE '%<pre><code>%' OR LOWER(P.Body) LIKE '%<code class="language-%">' THEN TRUE
            ELSE FALSE
        END AS ContainsCodeBlock,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS EditHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        COALESCE(array_length(string_to_array(substring(P.Tags FROM 2 FOR length(P.Tags)-2), '><'), 1), 0) AS TagCountFromPostString
    FROM
        Posts P
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.LastEditDate, P.LastActivityDate,
        P.ViewCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.Body, P.Title, P.Tags
),
TagPerformance AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        COUNT(DISTINCT P.Id) AS TotalQuestionsWithTag,
        COALESCE(AVG(P.Score), 0.0) AS AvgQuestionScoreForTag,
        COALESCE(SUM(P.AnswerCount), 0) AS TotalAnswersForTagQuestions,
        (SELECT COUNT(DISTINCT U_Inner.Id)
         FROM Users U_Inner
         JOIN Posts Q_Inner ON U_Inner.Id = Q_Inner.OwnerUserId
         WHERE Q_Inner.PostTypeId = 1 AND Q_Inner.Tags LIKE '%' || T.TagName || '%') AS DistinctAskUsersWithTag
    FROM
        Tags T
    LEFT JOIN
        Posts P ON P.PostTypeId = 1 AND P.Tags LIKE '%' || T.TagName || '%'
    WHERE
        T.TagName IS NOT NULL
    GROUP BY
        T.Id, T.TagName
    HAVING
        COUNT(DISTINCT P.Id) > 0
),
UserAcceptedAnswerInfo AS (
    SELECT
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Id AS QuestionId,
        Q.AcceptedAnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.CreationDate AS AnswerCreationDate,
        (SELECT C_AA.Text FROM Comments C_AA WHERE A.Id = C_AA.PostId ORDER BY C_AA.CreationDate DESC LIMIT 1) AS LatestAcceptedAnswerComment,
        ROW_NUMBER() OVER(PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate DESC, A.CreationDate DESC) AS rn
    FROM
        Posts Q
    INNER JOIN
        Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    WHERE
        Q.PostTypeId = 1 AND Q.AcceptedAnswerId IS NOT NULL
),
UserCommentSummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        COUNT(DISTINCT P.Id) AS DistinctPostsCommentedOn,
        MAX(C.CreationDate) AS LastCommentDate
    FROM
        Users U
    JOIN
        Comments C ON U.Id = C.UserId
    JOIN
        Posts P ON C.PostId = P.Id
    GROUP BY
        U.Id
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserRegistrationDate,
    U.LastAccessDate,
    'Post-Centric' AS UserFocusType,
    UPS.TotalPostsOwned,
    UPS.QuestionsAsked,
    UPS.AnswersGiven,
    UPS.TotalPostScore,
    UPS.AvgQuestionScore,
    UPS.AvgAnswerScore,
    UPS.TotalBadges,
    UPS.GoldBadges,
    UPS.TotalUpvotesReceivedOnPosts,
    UPS.TotalDownvotesReceivedOnPosts,
    UPS.TotalUpvotesGiven,
    UPS.TotalDownvotesGiven,
    COALESCE(PDA.EditHistoryCount, 0) AS TotalPostEdits,
    COALESCE(PDA.CloseHistoryCount, 0) AS TotalPostCloseEvents,
    PDA.PostAgeDays AS CurrentPostAgeDays,
    PDA.ContainsCodeBlock,
    PDA.AvgCommentScore AS PostAvgCommentScore,
    TP_Main.TagName AS TopTagByAvgScore,
    TP_Main.AvgQuestionScoreForTag,
    TP_Main.TotalAnswersForTagQuestions,
    UAA.LatestAcceptedAnswerComment,
    RANK() OVER (ORDER BY U.Reputation DESC, UPS.TotalUpvotesReceivedOnPosts DESC, UPS.AnswersGiven DESC) AS UserEngagementRank,
    CAST(NULLIF(UPS.QuestionsAsked + UPS.AnswersGiven, 0) AS DECIMAL) /
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - U.CreationDate)) / (60 * 60 * 24) + 1) AS ActivityPerDayRatio,
    CASE
        WHEN U.Reputation > 5000 AND UPS.GoldBadges >= 3 AND UPS.AnswersGiven > 50 THEN 'Power User'
        WHEN U.Reputation > 1000 AND UPS.TotalBadges >= 10 THEN 'Active Contributor'
        ELSE 'Casual User'
    END AS UserCategory,
    UPPER(SUBSTRING(COALESCE(U.DisplayName, 'UNKNOWN') FROM 1 FOR 3)) || LPAD(CAST(U.Id AS TEXT), 7, '0') AS UserIdentifierCode,
    EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Name = 'Fanatic') AS HasSpecificBadge,
    COALESCE(CASE
        WHEN U.Location ILIKE '%United States%' OR U.Location ILIKE '%USA%' OR U.Location ILIKE '%US' THEN 'US'
        WHEN U.Location ILIKE '%India%' THEN 'India'
        WHEN U.Location IS NULL OR TRIM(U.Location) = '' THEN 'Unknown'
        ELSE 'Other'
    END, 'Unknown') AS UserLocationRegion,
    EXTRACT(EPOCH FROM (COALESCE(P_Main.ClosedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - P_Main.CreationDate)) / (60 * 60 * 24 * 30) AS MonthsUntilClosed,
    (SELECT COUNT(Link.Id) FROM PostLinks Link WHERE Link.PostId = P_Main.Id AND Link.LinkTypeId = 1) AS OutboundLinksFromMainPost,
    (SELECT COUNT(Link.Id) FROM PostLinks Link WHERE Link.RelatedPostId = P_Main.Id AND Link.LinkTypeId = 1) AS InboundLinksToMainPost
FROM
    Users U
INNER JOIN
    UserPostVoteSummary UPS ON U.Id = UPS.UserId
LEFT JOIN LATERAL
    (SELECT P.* FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId IN (1,2) ORDER BY P.CreationDate DESC, P.Score DESC LIMIT 1) P_Main ON TRUE
LEFT JOIN
    PostDetailedAnalysis PDA ON P_Main.Id = PDA.PostId
LEFT JOIN LATERAL
    (SELECT TP_Inner.* FROM TagPerformance TP_Inner WHERE TP_Inner.DistinctAskUsersWithTag > 1 AND TP_Inner.AvgQuestionScoreForTag > 5 ORDER BY TP_Inner.AvgQuestionScoreForTag DESC LIMIT 1) TP_Main ON TRUE
LEFT JOIN
    UserAcceptedAnswerInfo UAA ON U.Id = UAA.QuestionOwnerId AND UAA.rn = 1
WHERE
    U.Reputation >= 1000
    AND UPS.TotalPostsOwned >= 5
    AND UPS.TotalUpvotesReceivedOnPosts > UPS.TotalDownvotesReceivedOnPosts * 2
    AND PDA.ContainsCodeBlock IS NOT NULL
    AND P_Main.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '3 years')
    AND (LOWER(P_Main.Body) LIKE '%sql%' OR LOWER(P_Main.Body) LIKE '%database%' OR LOWER(P_Main.Title) LIKE '%performance%')
    AND P_Main.Score >= 10
    AND EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1)
UNION ALL
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserRegistrationDate,
    U.LastAccessDate,
    'Comment-Centric' AS UserFocusType,
    COALESCE(UPS.TotalPostsOwned, 0) AS TotalPostsOwned,
    COALESCE(UPS.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UPS.AnswersGiven, 0) AS AnswersGiven,
    COALESCE(UPS.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(UPS.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(UPS.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(UPS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UPS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UPS.TotalUpvotesReceivedOnPosts, 0) AS TotalUpvotesReceivedOnPosts,
    COALESCE(UPS.TotalDownvotesReceivedOnPosts, 0) AS TotalDownvotesReceivedOnPosts,
    COALESCE(UPS.TotalUpvotesGiven, 0) AS TotalUpvotesGiven,
    COALESCE(UPS.TotalDownvotesGiven, 0) AS TotalDownvotesGiven,
    0 AS TotalPostEdits,
    0 AS TotalPostCloseEvents,
    NULL AS CurrentPostAgeDays,
    FALSE AS ContainsCodeBlock,
    UCS.AvgCommentScore AS PostAvgCommentScore,
    NULL AS TopTagByAvgScore,
    NULL AS AvgQuestionScoreForTag,
    NULL AS TotalAnswersForTagQuestions,
    NULL AS LatestAcceptedAnswerComment,
    RANK() OVER (ORDER BY U.Reputation DESC, UCS.TotalCommentsMade DESC, UCS.TotalCommentScore DESC) AS UserEngagementRank,
    CAST(NULLIF(UCS.TotalCommentsMade, 0) AS DECIMAL) /
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - U.CreationDate)) / (60 * 60 * 24) + 1) AS ActivityPerDayRatio,
    CASE
        WHEN UCS.TotalCommentsMade > 500 AND UCS.TotalCommentScore > 1000 THEN 'Pro Commenter'
        WHEN UCS.TotalCommentsMade > 100 AND UCS.AvgCommentScore >= 3 THEN 'Engaged Commenter'
        ELSE 'Occasional Commenter'
    END AS UserCategory,
    UPPER(SUBSTRING(COALESCE(U.DisplayName, 'ANON') FROM 1 FOR 3)) || '-' || LPAD(CAST(U.Id AS TEXT), 7, '0') AS UserIdentifierCode,
    EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Name = 'Commentator') AS HasSpecificBadge,
    COALESCE(CASE
        WHEN U.Location ILIKE '%Europe%' THEN 'Europe'
        WHEN U.Location ILIKE '%Asia%' THEN 'Asia'
        WHEN U.Location IS NULL OR TRIM(U.Location) = '' THEN 'Unknown'
        ELSE 'Other'
    END, 'Unknown') AS UserLocationRegion,
    NULL AS MonthsUntilClosed,
    NULL AS OutboundLinksFromMainPost,
    NULL AS InboundLinksToMainPost
FROM
    Users U
INNER JOIN
    UserCommentSummary UCS ON U.Id = UCS.UserId
LEFT JOIN
    UserPostVoteSummary UPS ON U.Id = UPS.UserId
WHERE
    U.Reputation >= 500
    AND UCS.TotalCommentsMade >= 50
    AND UCS.AvgCommentScore >= 1
    AND NOT EXISTS (SELECT 1 FROM Posts P WHERE P.OwnerUserId = U.Id AND P.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year'))
ORDER BY
    UserEngagementRank ASC, UserId ASC
LIMIT 200;