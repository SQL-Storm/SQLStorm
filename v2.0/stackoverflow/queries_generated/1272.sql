-- {"query": "1272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3068} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregates various activity counts for each user, including complex calculations and null handling.
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'AnonymousUser') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V_Given.Id) FILTER (WHERE V_Given.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(DISTINCT V_Given.Id) FILTER (WHERE V_Given.VoteTypeId = 3) AS DownvotesGiven,
        (
            SELECT SUM(V_Received.BountyAmount)
            FROM Votes V_Received
            WHERE V_Received.PostId IN (SELECT P_Inner.Id FROM Posts P_Inner WHERE P_Inner.OwnerUserId = U.Id)
            AND V_Received.VoteTypeId = 9 -- BountyClose
        ) AS TotalBountyReceived,
        (
            SELECT COUNT(DISTINCT PH_Inner.Id)
            FROM PostHistory PH_Inner
            WHERE PH_Inner.UserId = U.Id
            AND PH_Inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        ) AS TotalPostEdits,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS ReputationRank
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEngagementMetrics AS (
    -- CTE 2: Calculates engagement metrics for posts, including window functions and specific post type filtering.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        COALESCE(P.Title, 'No Title') AS PostTitle,
        P.Tags,
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS RollingAvgScore30Days,
        LAG(P.ViewCount, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostViewCount,
        COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicateLinkCount
    FROM
        Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE
        P.PostTypeId IN (1, 2) -- Questions and Answers
        AND P.CreationDate >= '2020-01-01' -- Recent posts
    GROUP BY
        P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags
),
MonthlyTagPerformance AS (
    -- CTE 3: Analyzes tag performance monthly, uses string manipulation and complex ranking.
    SELECT
        EXTRACT(YEAR FROM PEM.PostCreationDate) AS PostYear,
        EXTRACT(MONTH FROM PEM.PostCreationDate) AS PostMonth,
        unnest(string_to_array(substring(PEM.Tags, 2, length(PEM.Tags) - 2), '><')) AS TagName,
        COUNT(PEM.PostId) AS MonthlyTagPostCount,
        AVG(PEM.PostScore) AS MonthlyAvgTagScore,
        SUM(PEM.ViewCount) AS MonthlyTotalTagViews,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM PEM.PostCreationDate), EXTRACT(MONTH FROM PEM.PostCreationDate) ORDER BY COUNT(PEM.PostId) DESC, AVG(PEM.PostScore) DESC) AS MonthlyTagRank
    FROM
        PostEngagementMetrics PEM
    WHERE
        PEM.Tags IS NOT NULL AND LENGTH(TRIM(PEM.Tags)) > 2 -- Ensure valid tags exist
    GROUP BY
        1, 2, 3
),
UsersWithRecentBadges AS (
    -- CTE 4: Identifies users who received Gold badges recently, using correlated subquery logic.
    SELECT
        UAS.UserId,
        COUNT(B.Id) AS GoldBadgesLastYear
    FROM
        UserActivitySummary UAS
    INNER JOIN Badges B ON UAS.UserId = B.UserId
    WHERE
        B.Class = 1 -- Gold Badge
        AND B.Date >= UAS.UserLastAccessDate - INTERVAL '1 year' -- Acquired in last year relative to user's last access
    GROUP BY
        UAS.UserId
),
TopQuestionContributors AS (
    -- CTE 5: Users who have contributed questions with high engagement.
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS HighScoreQuestions,
        SUM(P.Score) AS TotalQuestionScore
    FROM Users U
    INNER JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1 AND P.Score > 50
    GROUP BY U.Id
    HAVING COUNT(P.Id) >= 5
),
ActiveCommentersWithoutQuestions AS (
    -- CTE 6: Users who comment a lot but rarely post questions, using an EXCEPT set operator.
    SELECT DISTINCT C.UserId
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    EXCEPT
    SELECT DISTINCT P.OwnerUserId
    FROM Posts P
    WHERE P.PostTypeId = 1
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalComments,
    UAS.UpvotesGiven,
    UAS.DownvotesGiven,
    UAS.TotalBountyReceived,
    UAS.TotalPostEdits,
    UAS.ReputationRank,
    COALESCE(URB.GoldBadgesLastYear, 0) AS RecentGoldBadges,
    (
        -- Correlated subquery: Get the top-scoring comment text for the user's highest viewed post
        SELECT
            C.Text
        FROM Comments C
        INNER JOIN PostEngagementMetrics PEM_Inner ON C.PostId = PEM_Inner.PostId
        WHERE
            PEM_Inner.OwnerUserId = UAS.UserId
            AND PEM_Inner.PostTypeId = 1 -- Only questions
            AND PEM_Inner.ViewCount = (SELECT MAX(PEM_Max.ViewCount) FROM PostEngagementMetrics PEM_Max WHERE PEM_Max.OwnerUserId = UAS.UserId AND PEM_Max.PostTypeId = 1)
        ORDER BY
            C.Score DESC, C.CreationDate DESC
        LIMIT 1
    ) AS TopCommentOnHighestViewedQuestion,
    PEM_Latest.PostTitle AS LatestPostTitle,
    PEM_Latest.PostScore AS LatestPostScore,
    PEM_Latest.RollingAvgScore30Days AS LatestPostRollingAvgScore,
    COALESCE(MP_QuestionTag.TagName, MP_AnswerTag.TagName, 'NoMajorTag') AS MostDominantRecentTag,
    MP_QuestionTag.MonthlyTagRank AS QuestionTagRank,
    MP_AnswerTag.MonthlyTagRank AS AnswerTagRank,
    CASE
        WHEN UAS.Reputation > 50000 AND UAS.TotalPosts > 500 AND UAS.TotalPostEdits > 100 THEN 'Legendary Contributor'
        WHEN UAS.Reputation > 10000 AND UAS.TotalPosts > 100 AND UAS.UpvotesGiven > 500 THEN 'Highly Active Expert'
        WHEN UAS.Reputation > 1000 AND UAS.TotalComments > 200 THEN 'Engaged Commenter'
        ELSE 'General Participant'
    END AS UserCategory,
    EXISTS (
        -- Check if user is among top question contributors
        SELECT 1 FROM TopQuestionContributors TQC WHERE TQC.UserId = UAS.UserId
    ) AS IsTopQuestionContributor,
    EXISTS (
        -- Check if user is an active commenter but not a question poster
        SELECT 1 FROM ActiveCommentersWithoutQuestions ACWQ WHERE ACWQ.UserId = UAS.UserId
    ) AS IsPureCommenter,
    NULLIF(TRIM(LOWER(SUBSTRING(U.Location, 1, 10))), '') AS ShortLocationDescription,
    SPLIT_PART(REPLACE(REPLACE(U.WebsiteUrl, 'http://', ''), 'https://', ''), '/', 1) AS WebsiteDomain
FROM
    UserActivitySummary UAS
INNER JOIN Users U ON UAS.UserId = U.Id
LEFT JOIN UsersWithRecentBadges URB ON UAS.UserId = URB.UserId
LEFT JOIN (
    -- Derived table for the user's latest post's engagement metrics
    SELECT
        PEM.PostId, PEM.OwnerUserId, PEM.PostTitle, PEM.PostScore, PEM.RollingAvgScore30Days,
        ROW_NUMBER() OVER (PARTITION BY PEM.OwnerUserId ORDER BY PEM.PostCreationDate DESC, PEM.PostScore DESC) as rn
    FROM PostEngagementMetrics PEM
    WHERE PEM.PostTypeId = 1 -- Only latest question
) PEM_Latest ON UAS.UserId = PEM_Latest.OwnerUserId AND PEM_Latest.rn = 1
LEFT JOIN (
    -- Join for the most dominant tag from user's questions in the month of their latest post
    SELECT DISTINCT ON (EXTRACT(YEAR FROM PEM_Inner.PostCreationDate), EXTRACT(MONTH FROM PEM_Inner.PostCreationDate), PEM_Inner.OwnerUserId)
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate) AS PostYear,
        EXTRACT(MONTH FROM PEM_Inner.PostCreationDate) AS PostMonth,
        PEM_Inner.OwnerUserId,
        MT.TagName, MT.MonthlyTagRank
    FROM PostEngagementMetrics PEM_Inner
    JOIN MonthlyTagPerformance MT ON
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate) = MT.PostYear AND
        EXTRACT(MONTH FROM PEM_Inner.PostCreationDate) = MT.PostMonth AND
        PEM_Inner.Tags LIKE CONCAT('%<', MT.TagName, '>%')
    WHERE PEM_Inner.PostTypeId = 1
    ORDER BY
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate), EXTRACT(MONTH FROM PEM_Inner.PostCreationDate), PEM_Inner.OwnerUserId, MT.MonthlyTagRank ASC, MT.MonthlyTagPostCount DESC
) MP_QuestionTag ON UAS.UserId = MP_QuestionTag.OwnerUserId AND
                    EXTRACT(YEAR FROM PEM_Latest.PostCreationDate) = MP_QuestionTag.PostYear AND
                    EXTRACT(MONTH FROM PEM_Latest.PostCreationDate) = MP_QuestionTag.PostMonth
LEFT JOIN (
    -- Join for the most dominant tag from user's answers in the month of their latest post (if any)
    SELECT DISTINCT ON (EXTRACT(YEAR FROM PEM_Inner.PostCreationDate), EXTRACT(MONTH FROM PEM_Inner.PostCreationDate), PEM_Inner.OwnerUserId)
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate) AS PostYear,
        EXTRACT(MONTH FROM PEM_Inner.PostCreationDate) AS PostMonth,
        PEM_Inner.OwnerUserId,
        MT.TagName, MT.MonthlyTagRank
    FROM PostEngagementMetrics PEM_Inner
    JOIN MonthlyTagPerformance MT ON
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate) = MT.PostYear AND
        EXTRACT(MONTH FROM PEM_Inner.PostCreationDate) = MT.PostMonth AND
        PEM_Inner.Tags LIKE CONCAT('%<', MT.TagName, '>%')
    WHERE PEM_Inner.PostTypeId = 2
    ORDER BY
        EXTRACT(YEAR FROM PEM_Inner.PostCreationDate), EXTRACT(MONTH FROM PEM_Inner.PostCreationDate), PEM_Inner.OwnerUserId, MT.MonthlyTagRank ASC, MT.MonthlyTagPostCount DESC
) MP_AnswerTag ON UAS.UserId = MP_AnswerTag.OwnerUserId AND
                   EXTRACT(YEAR FROM PEM_Latest.PostCreationDate) = MP_AnswerTag.PostYear AND
                   EXTRACT(MONTH FROM PEM_Latest.PostCreationDate) = MP_AnswerTag.PostMonth
WHERE
    UAS.Reputation > 500 -- Focus on more established users
    AND (
        UAS.TotalPosts > 10
        OR UAS.TotalComments > 20
        OR UAS.UpvotesGiven > 50
    )
    AND UAS.UserLastAccessDate > UAS.UserCreationDate + INTERVAL '1 year' -- Users active for over a year
ORDER BY
    UAS.Reputation DESC, UAS.UserLastAccessDate DESC, UAS.TotalPosts DESC
LIMIT 5000;
