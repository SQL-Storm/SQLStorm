-- {"query": "1884.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4269} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates user-level post statistics, including average scores and first/last activity dates.
    -- Demonstrates: INNER JOIN, GROUP BY, Aggregate Functions (COUNT, SUM, AVG, MIN, MAX), CASE expressions, date filtering.
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
    WHERE U.CreationDate >= '2019-01-01' -- Filter for users created after a certain date
      AND P.CreationDate BETWEEN U.CreationDate AND U.LastAccessDate -- Ensure post dates are within user's activity window
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5 -- Only consider users with more than 5 posts
),
PostClosureAnalysis AS (
    -- CTE 2: Identifies closed questions, their reasons, and calculates time to closure.
    -- Demonstrates: INNER JOIN, LEFT JOIN, String Functions (SUBSTRING, POSITION, LENGTH), CAST, Date Arithmetic (EXTRACT), Window Function (LAG).
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS QuestionOwnerId,
        P.CreationDate AS QuestionCreationDate,
        P.Title AS QuestionTitle,
        PH.CreationDate AS CloseHistoryDate,
        CR.Name AS CloseReasonName,
        CAST(SUBSTRING(PH.Comment, POSITION('=' IN PH.Comment) + 1, LENGTH(PH.Comment)) AS SMALLINT) AS CloseReasonId,
        -- Calculate the duration from the previous history event (or post creation) to this closure event.
        -- This uses LAG to find the prior timestamp for the same post.
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate))) / 3600 AS HoursSincePreviousEditOrCreationToClose
    FROM Posts AS P
    INNER JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN CloseReasonTypes AS CR ON CAST(SUBSTRING(PH.Comment, POSITION('=' IN PH.Comment) + 1, LENGTH(PH.Comment)) AS SMALLINT) = CR.Id
    WHERE P.PostTypeId = 1 -- Only questions
      AND PH.PostHistoryTypeId = 10 -- Post Closed event
      AND PH.Comment LIKE 'CloseReasonId=%' -- Ensure the comment contains the CloseReasonId
),
UserPostMetrics AS (
    -- CTE 3: Combines user engagement with post closure details and adds comment statistics.
    -- Demonstrates: LEFT JOIN, Correlated Subquery (AvgCommentLength), Aggregate Functions, COALESCE.
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
        (SELECT COALESCE(AVG(LENGTH(C.Text)), 0)
         FROM Comments AS C
         WHERE C.UserId = UES.UserId
           AND C.CreationDate BETWEEN UES.EarliestPostDate AND UES.LatestPostDate
           AND C.Text IS NOT NULL AND LENGTH(C.Text) > 5 -- Correlated subquery for average comment length by the user
        ) AS AvgCommentLengthByAuthor,
        COALESCE(
            (SELECT COUNT(DISTINCT CM.Id)
             FROM Comments AS CM
             INNER JOIN Posts AS P ON CM.PostId = P.Id
             WHERE P.OwnerUserId = UES.UserId AND CM.UserId IS NULL -- Comments by anonymous users on the user's posts
            ), 0) AS AnonCommentsOnUserPosts
    FROM UserEngagementSummary AS UES
    LEFT JOIN PostClosureAnalysis AS PCA ON UES.UserId = PCA.QuestionOwnerId
    GROUP BY UES.UserId, UES.UserName, UES.Reputation, UES.TotalPosts, UES.QuestionCount, UES.AnswerCount, UES.AvgQuestionScore, UES.AvgAnswerScore,
             UES.EarliestPostDate, UES.LatestPostDate, UES.TotalGivenUpVotes, UES.TotalGivenDownVotes
),
DetailedBadgeAndTagMetrics AS (
    -- CTE 4: Gathers badge information and identifies the most frequently used tag for each user.
    -- Demonstrates: LEFT JOIN, String Functions (string_to_array, UNNEST, SUBSTRING, LENGTH, TRIM, LOWER), Window Function (ROW_NUMBER).
    WITH TagCountsPerUser AS (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))) AS TagName,
            COUNT(P.Id) AS TagUsageCount
        FROM Posts AS P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
        GROUP BY P.OwnerUserId, TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))))
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
    -- CTE 5: Aggregates votes received on posts owned by the user.
    -- Demonstrates: LEFT JOIN, Aggregate Functions (SUM), CASE expressions.
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
    -- CTE 6: Combines all metrics and calculates a composite impact score and rank for users.
    -- Demonstrates: Multiple LEFT JOINs, complex mathematical expressions, COALESCE, Window Function (DENSE_RANK).
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
        -- Calculate a composite impact score using various weighted metrics
        (UPM.Reputation * 0.15 +
         UPM.AvgQuestionScore * 0.20 +
         UPM.AvgAnswerScore * 0.25 +
         (COALESCE(UVA.TotalUpvotesReceived, 0) - COALESCE(UVA.TotalDownvotesReceived, 0)) * 0.10 +
         DBATM.GoldBadges * 50 +
         UPM.TotalGivenUpVotes * 0.05 - -- Upvotes given by user
         UPM.TotalGivenDownVotes * 0.02 - -- Downvotes given by user
         (UPM.DuplicateClosedCount + UPM.OffTopicClosedCount) * 20 -- Penalty for closed questions
        ) AS UserImpactScore,
        DENSE_RANK() OVER (ORDER BY (UPM.Reputation * 0.15 + UPM.AvgQuestionScore * 0.20 + UPM.AvgAnswerScore * 0.25 + (COALESCE(UVA.TotalUpvotesReceived, 0) - COALESCE(UVA.TotalDownvotesReceived, 0)) * 0.10 + DBATM.GoldBadges * 50 + UPM.TotalGivenUpVotes * 0.05 - UPM.TotalGivenDownVotes * 0.02 - (UPM.DuplicateClosedCount + UPM.OffTopicClosedCount) * 20) DESC) AS OverallImpactRank
    FROM UserPostMetrics AS UPM
    LEFT JOIN DetailedBadgeAndTagMetrics AS DBATM ON UPM.UserId = DBATM.UserId
    LEFT JOIN UserVoteAggregates AS UVA ON UPM.UserId = UVA.UserId
),
UsersWithHighImpactOrSpecificInterests AS (
    -- CTE 7: Filters users based on two different criteria, ready for UNION ALL.
    -- Demonstrates: Filtering based on complex score and specific badge/tag criteria.
    SELECT
        FUR.*,
        'High Impact & Closed Posts' AS UserCategory
    FROM FinalUserRanking AS FUR
    WHERE FUR.OverallImpactRank <= 100 -- Top 100 users by overall impact
      AND FUR.TotalClosedQuestions > 0 -- Must have at least one closed question
      AND FUR.AvgHoursToFirstClose BETWEEN 0 AND 48 -- Closed within 2 days
      AND FUR.MostFrequentTag IS NOT NULL AND FUR.MostFrequentTag NOT IN ('java', 'c#', 'python') -- Exclude some popular tags
      AND FUR.AvgCommentLengthByAuthor >= 20 -- Average comment length must be substantial
      AND FUR.TotalUpvotesReceived IS NOT NULL AND FUR.TotalUpvotesReceived > (FUR.TotalDownvotesReceived * 3) -- Significant positive vote ratio
),
UsersWithHighReputationAndActivity AS (
    SELECT
        FUR.*,
        'High Reputation & Activity' AS UserCategory
    FROM FinalUserRanking AS FUR
    WHERE FUR.Reputation > 10000 -- High reputation users
      AND FUR.GoldBadges >= 5 -- At least 5 gold badges
      AND FUR.QuestionCount >= 10 AND FUR.AnswerCount >= 30 -- Substantial question and answer activity
      AND FUR.AnonCommentsOnUserPosts = 0 -- No anonymous comments on their posts (implies good post clarity/management)
      AND FUR.UserImpactScore > 5000 -- Also has a high impact score
)
-- Final Query: Combines the two sets of users using UNION ALL, applies final filters,
-- and includes complex string manipulation for a user's 'AboutMe' section.
-- Demonstrates: UNION ALL, complex WHERE clause, NULL logic, string manipulation (SUBSTRING, POSITION, LENGTH), COALESCE.
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
        WHEN A.UserImpactScore > 15000 AND A.GoldBadges >= 10 THEN 'Elite Contributor'
        WHEN A.UserImpactScore > 10000 AND A.TotalClosedQuestions <= 1 THEN 'Trusted Expert'
        WHEN A.UserImpactScore > 5000 AND A.AvgCommentLengthByAuthor >= 50 THEN 'Engaged Communicator'
        ELSE 'Active Participant'
    END AS UserPersona,
    -- Extract a snippet from the user's AboutMe, assuming basic <p>...</p> HTML structure
    COALESCE(
        SUBSTRING(U.AboutMe, POSITION('<p>' IN U.AboutMe) + 3,
            CASE
                WHEN POSITION('</p>' IN U.AboutMe) > POSITION('<p>' IN U.AboutMe) + 3
                THEN POSITION('</p>' IN U.AboutMe) - (POSITION('<p>' IN U.AboutMe) + 3)
                ELSE 0
            END
        ), 'No public "About Me" snippet available.') AS AboutMeFirstParagraphSnippet,
    U.Location,
    U.WebsiteUrl IS NOT NULL AS HasWebsite
FROM UsersWithHighImpactOrSpecificInterests AS A
INNER JOIN Users AS U ON A.UserId = U.Id -- Join back to Users for AboutMe, Location, WebsiteUrl
WHERE U.Location IS NOT NULL AND LENGTH(TRIM(U.Location)) > 5 -- Filter users with a non-trivial location
  AND (U.AboutMe LIKE '%developer%' OR U.AboutMe LIKE '%engineer%' OR U.WebsiteUrl IS NOT NULL) -- Look for specific keywords in AboutMe or if they have a website
  AND A.Reputation / (NULLIF(A.TotalPosts, 0)) > 50 -- Reputation density check
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
        WHEN B.UserImpactScore > 15000 AND B.GoldBadges >= 10 THEN 'Elite Contributor'
        WHEN B.UserImpactScore > 10000 AND B.TotalClosedQuestions <= 1 THEN 'Trusted Expert'
        WHEN B.UserImpactScore > 5000 AND B.AvgCommentLengthByAuthor >= 50 THEN 'Engaged Communicator'
        ELSE 'Active Participant'
    END AS UserPersona,
    COALESCE(
        SUBSTRING(U.AboutMe, POSITION('<p>' IN U.AboutMe) + 3,
            CASE
                WHEN POSITION('</p>' IN U.AboutMe) > POSITION('<p>' IN U.AboutMe) + 3
                THEN POSITION('</p>' IN U.AboutMe) - (POSITION('<p>' IN U.AboutMe) + 3)
                ELSE 0
            END
        ), 'No public "About Me" snippet available.') AS AboutMeFirstParagraphSnippet,
    U.Location,
    U.WebsiteUrl IS NOT NULL AS HasWebsite
FROM UsersWithHighReputationAndActivity AS B
INNER JOIN Users AS U ON B.UserId = U.Id
WHERE U.Location IS NOT NULL AND U.Location LIKE '%United States%' -- Filter for specific location
  AND B.TotalPosts > 100 -- Users with a large volume of content
  AND B.GoldBadges / (NULLIF(B.TotalBadges, 0)::NUMERIC) > 0.05 -- More than 5% of their badges are Gold
ORDER BY UserImpactScore DESC, Reputation DESC
LIMIT 500; -- Limit the final result set
