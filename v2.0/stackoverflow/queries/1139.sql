-- {"query": "1139.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3518} 
WITH QuestionEngagement AS (
    -- CTE 1: Identifies highly engaged questions based on view count, answer count, and average answer score.
    -- It also aggregates the names of gold badges held by the question owner.
    SELECT
        Q.Id AS QuestionId,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.AcceptedAnswerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        Q.AnswerCount,
        AVG(A.Score * 1.0) AS AvgAnswerScore, -- Calculate average answer score (float division)
        COUNT(A.Id) AS ActualAnswerCount,
        STRING_AGG(DISTINCT SUBSTRING(TRIM(B.Name), 1, 10), ',') AS TopBadgeNamesForQuestionOwner -- Aggregates first 10 chars of distinct gold badge names
    FROM
        Posts Q
    INNER JOIN
        Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Joins questions with their answers
    LEFT JOIN
        Badges B ON Q.OwnerUserId = B.UserId AND B.Class = 1 -- Links question owner to their gold badges
    WHERE
        Q.PostTypeId = 1 -- Only questions
        AND Q.ViewCount >= (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND ViewCount IS NOT NULL) * 1.5 -- 1.5 times the average view count for all questions
        AND Q.AnswerCount >= 5 -- Requires at least 5 reported answers
        AND Q.FavoriteCount IS NOT NULL -- Must have been favorited at least once
        AND Q.ClosedDate IS NULL -- Excludes closed questions
    GROUP BY
        Q.Id, Q.ViewCount, Q.Score, Q.OwnerUserId, Q.AcceptedAnswerId, Q.CreationDate, Q.LastActivityDate, Q.AnswerCount, Q.FavoriteCount, Q.ClosedDate
    HAVING
        AVG(A.Score * 1.0) > 3 -- Ensures answers to these questions have an average score above 3
),
UserAnswerPerformance AS (
    -- CTE 2: Calculates performance metrics for users based on their answers to highly engaged questions.
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT QE.QuestionId) AS AnsweredHighEngagementQuestionCount,
        SUM(A.Score) AS TotalAnswerScore,
        AVG(A.Score * 1.0) AS AvgAnswerScorePerUser,
        SUM(CASE WHEN A.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCountByThisUser,
        MAX(A.LastEditDate) AS LastAnswerEditDate
    FROM
        Posts A
    INNER JOIN
        QuestionEngagement QE ON A.ParentId = QE.QuestionId AND A.PostTypeId = 2 -- Links answers to highly engaged questions
    WHERE
        A.OwnerUserId IS NOT NULL
        AND A.CreationDate > '2020-01-01' -- Focuses on recent answers
    GROUP BY
        A.OwnerUserId
    HAVING
        COUNT(A.Id) >= 3 -- Requires at least 3 answers to such questions
),
UserQuestionPerformance AS (
    -- CTE 3: Calculates performance metrics for users based on their high-quality questions.
    SELECT
        Q.OwnerUserId AS UserId,
        COUNT(DISTINCT Q.Id) AS PostedHighEngagementQuestionCount,
        SUM(Q.Score) AS TotalQuestionScore,
        AVG(Q.Score * 1.0) AS AvgQuestionScorePerUser,
        SUM(CASE WHEN Q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnsweredQuestionCount, -- Number of user's own questions with an accepted answer
        MAX(Q.LastActivityDate) AS LastQuestionActivityDate
    FROM
        Posts Q
    WHERE
        Q.PostTypeId = 1
        AND Q.OwnerUserId IS NOT NULL
        AND Q.ViewCount > 5000 -- High view count threshold for questions
        AND Q.AnswerCount >= 10
        AND Q.Score > 50
        AND Q.CreationDate > '2019-01-01' -- Focuses on recent questions
    GROUP BY
        Q.OwnerUserId
    HAVING
        COUNT(Q.Id) >= 2 -- Requires at least two such questions
),
UserOverallEngagement AS (
    -- CTE 4: Aggregates general engagement metrics for users (comments, post history, votes, badges).
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserReceivedUpVotes,
        U.DownVotes AS UserReceivedDownVotes,
        U.Location,
        COUNT(DISTINCT C.Id) AS TotalCommentCount,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditHistoryCount, -- Counts specific edit history types
        MAX(PH.CreationDate) AS LastHistoryDate,
        COUNT(DISTINCT V.Id) AS TotalVotesGivenByOwner, -- Votes cast by this user
        SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UpvotesOrFavoritesGiven,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM
        Users U
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId IN (2, 3, 5) -- Filters for UpMod, DownMod, Favorite vote types
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE
        U.Reputation > 500 -- Base reputation filter
        AND U.AboutMe IS NOT NULL -- User must have an "About Me" section
        AND LENGTH(U.DisplayName) > 5 -- Display name must be longer than 5 characters
        AND U.DisplayName LIKE '%User%' -- Example string pattern matching
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
),
FinalUserMetrics AS (
    -- CTE 5: Combines all performance and engagement metrics for each user.
    SELECT
        UOE.UserId,
        UOE.DisplayName,
        UOE.Reputation,
        UOE.UserCreationDate,
        UOE.LastAccessDate,
        UOE.UserProfileViews,
        UOE.UserReceivedUpVotes,
        UOE.UserReceivedDownVotes,
        UOE.Location,
        COALESCE(UAP.AnsweredHighEngagementQuestionCount, 0) AS AnsweredHighEngagementQuestionCount,
        COALESCE(UAP.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(UAP.AvgAnswerScorePerUser, 0) AS AvgAnswerScorePerUser,
        COALESCE(UAP.AcceptedAnswerCountByThisUser, 0) AS AcceptedAnswerCountByThisUser,
        UAP.LastAnswerEditDate,
        COALESCE(UQP.PostedHighEngagementQuestionCount, 0) AS PostedHighEngagementQuestionCount,
        COALESCE(UQP.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(UQP.AvgQuestionScorePerUser, 0) AS AvgQuestionScorePerUser,
        COALESCE(UQP.AcceptedAnsweredQuestionCount, 0) AS AcceptedAnsweredQuestionCount,
        UQP.LastQuestionActivityDate,
        UOE.TotalCommentCount,
        UOE.TotalCommentScore,
        UOE.TotalPostHistoryEntries,
        UOE.EditHistoryCount,
        UOE.LastHistoryDate,
        UOE.TotalVotesGivenByOwner,
        UOE.UpvotesOrFavoritesGiven,
        UOE.GoldBadgeCount,
        UOE.SilverBadgeCount,
        UOE.BronzeBadgeCount,
        EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - UOE.LastAccessDate)) AS DaysSinceLastAccess -- Calculates days since last access
    FROM
        UserOverallEngagement UOE
    LEFT JOIN
        UserAnswerPerformance UAP ON UOE.UserId = UAP.UserId
    LEFT JOIN
        UserQuestionPerformance UQP ON UOE.UserId = UQP.UserId
    WHERE
        (UAP.UserId IS NOT NULL OR UQP.UserId IS NOT NULL) -- Ensures user has either answered or posted high-engagement content
)
-- Main query for 'Answer Experts': Identifies and ranks users based on their answer contributions.
SELECT
    FUM.UserId,
    FUM.DisplayName,
    'AnswerExpert' AS UserRoleCategory,
    FUM.Reputation,
    FUM.GoldBadgeCount,
    FUM.SilverBadgeCount,
    FUM.BronzeBadgeCount,
    FUM.AnsweredHighEngagementQuestionCount,
    FUM.AvgAnswerScorePerUser,
    FUM.AcceptedAnswerCountByThisUser,
    FUM.TotalCommentCount,
    FUM.EditHistoryCount,
    FUM.DaysSinceLastAccess,
    NULLIF(FUM.Location, '') AS UserLocation, -- Replaces empty string location with NULL
    UPPER(LEFT(COALESCE(FUM.DisplayName, 'UNKNOWN'), 5)) AS DisplayNamePrefix, -- String manipulation
    -- Final Composite Score for Answer Experts: weighted sum of various metrics, with inactivity penalty.
    (
        FUM.AvgAnswerScorePerUser * 15 +
        LOG10(FUM.Reputation + 1) * 7 + -- Logarithmic scale for reputation
        SQRT(FUM.AnsweredHighEngagementQuestionCount) * 3 + -- Square root for diminishing returns on high counts
        FUM.AcceptedAnswerCountByThisUser * 5 +
        (FUM.GoldBadgeCount * 10 + FUM.SilverBadgeCount * 5 + FUM.BronzeBadgeCount * 1) -
        CASE WHEN FUM.DaysSinceLastAccess > 60 THEN FUM.DaysSinceLastAccess / 20.0 ELSE 0 END -- Inactivity penalty
    ) AS FinalCompositeScore,
    RANK() OVER (ORDER BY FUM.AvgAnswerScorePerUser DESC, FUM.Reputation DESC) AS OverallRank, -- Global rank by answer score and reputation
    LAG(FUM.Reputation, 1, 0) OVER (ORDER BY FUM.Reputation DESC) AS PreviousReputationUser, -- Reputation of the user immediately above in reputation rank
    NTH_VALUE(FUM.DisplayName, 5) OVER (ORDER BY FUM.Reputation DESC) AS FifthHighestReputationUser -- Display name of the 5th highest reputation user
FROM
    FinalUserMetrics FUM
WHERE
    FUM.AnsweredHighEngagementQuestionCount >= 5 -- Requires significant contribution as an answerer
    AND FUM.AvgAnswerScorePerUser > 5
    AND FUM.AcceptedAnswerCountByThisUser >= 2
    AND FUM.DaysSinceLastAccess < 180 -- Recently active
    AND FUM.GoldBadgeCount >= 1
    -- Correlated subquery: checks if any answer by this user received an 'AcceptedByOriginator' vote
    AND EXISTS (
        SELECT 1
        FROM Posts P_ANS
        JOIN Votes V_ACC ON P_ANS.Id = V_ACC.PostId
        WHERE P_ANS.OwnerUserId = FUM.UserId
        AND P_ANS.PostTypeId = 2
        AND V_ACC.VoteTypeId = 1 -- AcceptedByOriginator vote type
        LIMIT 1
    )

UNION ALL

-- Main query for 'Question Curators': Identifies and ranks users based on their question contributions.
SELECT
    FUM.UserId,
    FUM.DisplayName,
    'QuestionCurator' AS UserRoleCategory,
    FUM.Reputation,
    FUM.GoldBadgeCount,
    FUM.SilverBadgeCount,
    FUM.BronzeBadgeCount,
    FUM.PostedHighEngagementQuestionCount AS AnsweredHighEngagementQuestionCount, -- Renamed for UNION compatibility
    FUM.AvgQuestionScorePerUser AS AvgAnswerScorePerUser, -- Renamed for UNION compatibility
    FUM.AcceptedAnsweredQuestionCount AS AcceptedAnswerCountByThisUser, -- Renamed for UNION compatibility
    FUM.TotalCommentCount,
    FUM.EditHistoryCount,
    FUM.DaysSinceLastAccess,
    NULLIF(FUM.Location, '') AS UserLocation,
    UPPER(LEFT(COALESCE(FUM.DisplayName, 'UNKNOWN'), 5)) AS DisplayNamePrefix,
    -- Final Composite Score for Question Curators: similar weighted sum with different weights and penalties.
    (
        FUM.AvgQuestionScorePerUser * 12 +
        LOG10(FUM.Reputation + 1) * 6 +
        SQRT(FUM.PostedHighEngagementQuestionCount) * 4 +
        FUM.AcceptedAnsweredQuestionCount * 6 +
        (FUM.GoldBadgeCount * 8 + FUM.SilverBadgeCount * 4 + FUM.BronzeBadgeCount * 0.5) -
        CASE WHEN FUM.DaysSinceLastAccess > 90 THEN FUM.DaysSinceLastAccess / 15.0 ELSE 0 END
    ) AS FinalCompositeScore,
    RANK() OVER (ORDER BY FUM.AvgQuestionScorePerUser DESC, FUM.Reputation DESC) AS OverallRank,
    LAG(FUM.Reputation, 1, 0) OVER (ORDER BY FUM.Reputation DESC) AS PreviousReputationUser,
    NTH_VALUE(FUM.DisplayName, 5) OVER (ORDER BY FUM.Reputation DESC) AS FifthHighestReputationUser
FROM
    FinalUserMetrics FUM
WHERE
    FUM.PostedHighEngagementQuestionCount >= 3 -- Requires significant contribution as a questioner
    AND FUM.AvgQuestionScorePerUser > 10
    AND FUM.AcceptedAnsweredQuestionCount >= 1
    AND FUM.DaysSinceLastAccess < 365
    AND FUM.SilverBadgeCount >= 2
    -- Correlated subquery: checks if any question by this user was linked as a duplicate
    AND EXISTS (
        SELECT 1
        FROM Posts P_QUES
        JOIN PostLinks PL ON P_QUES.Id = PL.PostId
        WHERE P_QUES.OwnerUserId = FUM.UserId
        AND P_QUES.PostTypeId = 1
        AND PL.LinkTypeId = 3 -- Duplicate link type
        LIMIT 1
    )
ORDER BY
    FinalCompositeScore DESC, Reputation DESC
LIMIT 100;