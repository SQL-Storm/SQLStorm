-- {"query": "1678.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3644} 

WITH UserContributionSummary AS (
    -- Summarizes user activity, badge counts, and calculates average interaction time for users with multiple posts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT AVG(LENGTH(T.Text)) FROM Comments AS T WHERE T.UserId = U.Id AND T.Text IS NOT NULL) AS AvgCommentLength,
        EXTRACT(EPOCH FROM (MAX(P.CreationDate) - MIN(P.CreationDate))) / NULLIF(COUNT(P.Id) - 1, 0) AS AvgTimeBetweenPostsInSeconds,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY U.Id ORDER BY P.CreationDate) AS PreviousPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views
    HAVING COUNT(DISTINCT P.Id) > 5 -- Only consider users with more than 5 posts
),
PostDetailsBase AS (
    -- Gathers base information for questions and answers, including post history events, and ranks user posts.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount, -- Only relevant for PostTypeId = 1
        P.FavoriteCount,
        P.OwnerUserId,
        P.Title,
        P.Body, -- Include body for length calculation
        P.Tags,
        P.ParentId, -- Only relevant for PostTypeId = 2
        P.AcceptedAnswerId, -- Only relevant for PostTypeId = 1
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (35) THEN 1 ELSE 0 END) AS WasMigratedAway,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (36) THEN 1 ELSE 0 END) AS WasMigratedHere,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END), 'N/A') AS CloseReasonComment,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate ASC) AS UserPostScoreRank
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.OwnerUserId, P.Title, P.Body, P.Tags, P.ParentId, P.AcceptedAnswerId
),
TagPerformance AS (
    -- Calculates tag-specific metrics and identifies prominent tags from questions.
    SELECT
        T.TagName,
        SUM(PDB.PostScore) AS TotalTagScore,
        COUNT(DISTINCT PDB.PostId) AS TotalPostsWithTag,
        AVG(PDB.ViewCount) AS AvgTagViewCount,
        RANK() OVER (ORDER BY SUM(PDB.PostScore) DESC) AS TagScoreRank
    FROM PostDetailsBase AS PDB
    JOIN (SELECT Id, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS TagName FROM Posts WHERE Tags IS NOT NULL AND PostTypeId = 1) AS PT ON PDB.PostId = PT.Id
    JOIN Tags AS T ON PT.TagName = T.TagName
    WHERE PDB.PostTypeId = 1 -- Only questions for tag performance
    GROUP BY T.TagName
    HAVING COUNT(DISTINCT PDB.PostId) > 10
),
PostLinkInfluence AS (
    -- Explores influence based on linked and duplicate posts, also bounty and commenter reputation.
    SELECT
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        P.CreationDate,
        P.OwnerUserId,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        COALESCE(MAX(RelatedP.Score), 0) AS MaxRelatedPostScore,
        (
            SELECT SUM(V.BountyAmount)
            FROM Votes AS V
            WHERE V.PostId = P.Id AND V.VoteTypeId = 8 -- BountyStart
        ) AS TotalBountyAmountOffered,
        (
            SELECT AVG(U2.Reputation)
            FROM Users AS U2
            JOIN Comments AS C ON U2.Id = C.UserId
            WHERE C.PostId = P.Id
        ) AS AvgCommenterReputation,
        LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    LEFT JOIN Posts AS RelatedP ON PL.RelatedPostId = RelatedP.Id
    GROUP BY P.Id, P.Title, P.PostTypeId, P.CreationDate, P.OwnerUserId
)
-- Main query part 1: Influential Questions
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.TotalPosts,
    UCS.TotalQuestions,
    UCS.TotalAnswers,
    UCS.GoldBadges,
    PDB.PostId,
    PDB.Title AS PostTitle,
    'Question' AS PostType,
    PDB.PostScore,
    PDB.ViewCount AS PostViewCount,
    PDB.AnswerCount AS PostAnswerCount,
    PDB.FavoriteCount AS PostFavoriteCount,
    PDB.CloseReasonComment,
    PDB.WasClosed,
    PDB.WasMigratedAway,
    PLA.LinkedPostsCount,
    PLA.DuplicatePostsCount,
    PLA.MaxRelatedPostScore,
    TP.TagName AS MostPopularTagUsed,
    TP.TotalTagScore,
    TP.TagScoreRank,
    COALESCE(PLA.TotalBountyAmountOffered, 0) AS PostBounty,
    COALESCE(PLA.AvgCommenterReputation, 0.0) AS AvgCommenterReputationOnPost,
    CASE
        WHEN PDB.PostScore > 100 AND PDB.AnswerCount > 5 AND PDB.WasClosed = 0 THEN 'Highly Influential Open Question'
        WHEN PDB.PostScore > 50 AND PDB.WasClosed = 1 THEN 'Popular Closed Question'
        WHEN PDB.WasMigratedAway = 1 AND PLA.LinkedPostsCount > 0 THEN 'Migrated Question with Links'
        ELSE 'Other Notable Question'
    END AS PostInfluenceCategory,
    EXTRACT(DAY FROM (NOW() - PDB.PostCreationDate)) AS DaysSincePostCreation,
    (
        SELECT COUNT(DISTINCT C.UserId)
        FROM Comments AS C
        WHERE C.PostId = PDB.PostId
        AND C.CreationDate > PDB.PostCreationDate -- comments after post creation
        AND C.UserId IS NOT NULL -- ensure user exists
        AND C.UserId != UCS.UserId
    ) AS UniqueCommentersOnPost,
    UCS.AvgCommentLength,
    UCS.AvgTimeBetweenPostsInSeconds,
    LENGTH(PDB.Body) AS BodyLength,
    NULLIF(PDB.AnswerCount, 0) * 1.0 / NULLIF(PDB.ViewCount, 0) AS AnswerConversionRate -- for questions
FROM UserContributionSummary AS UCS
INNER JOIN PostDetailsBase AS PDB ON UCS.UserId = PDB.OwnerUserId
LEFT JOIN PostLinkInfluence AS PLA ON PDB.PostId = PLA.PostId
LEFT JOIN (
    -- Subquery to find the most popular tag for each post
    SELECT DISTINCT ON (P.Id)
        P.Id,
        T.TagName,
        TP_CTE.TotalTagScore,
        TP_CTE.TagScoreRank
    FROM Posts AS P
    JOIN (SELECT Id, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS TagName FROM Posts WHERE Tags IS NOT NULL) AS PT ON P.Id = PT.Id
    JOIN TagPerformance AS TP_CTE ON PT.TagName = TP_CTE.TagName
    ORDER BY P.Id, TP_CTE.TotalTagScore DESC, TP_CTE.TagScoreRank ASC
) AS TP ON PDB.PostId = TP.Id
WHERE
    PDB.PostTypeId = 1 -- Only questions
    AND UCS.TotalQuestions > 2 AND UCS.Reputation > 500
    AND PDB.PostScore > 10
    AND PDB.UserPostScoreRank <= 5 -- Top 5 questions by user score
    AND PDB.PostCreationDate >= '2022-01-01'
    AND PDB.PostCreationDate <= '2024-01-01'
    AND PDB.Title IS NOT NULL
    AND PDB.Title LIKE '%[Ss]ql%' -- Questions containing 'sql' (case-insensitive)
    AND (PLA.MaxRelatedPostScore > 0 OR PLA.LinkedPostsCount > 0)
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory AS PH_INNER
        WHERE PH_INNER.PostId = PDB.PostId
        AND PH_INNER.PostHistoryTypeId = 12 -- Post Deleted
        AND PH_INNER.CreationDate > PDB.CreationDate -- After post creation
    )

UNION ALL

-- Main query part 2: Influential Answers
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.TotalPosts,
    UCS.TotalQuestions,
    UCS.TotalAnswers,
    UCS.GoldBadges,
    PDB.PostId,
    COALESCE(Q.Title, 'N/A Parent Title') AS PostTitle, -- Get parent question's title for answers
    'Answer' AS PostType,
    PDB.PostScore,
    Q.ViewCount AS PostViewCount, -- Get view count from parent question
    Q.AnswerCount AS PostAnswerCount, -- Get answer count from parent question
    PDB.FavoriteCount AS PostFavoriteCount,
    PDB.CloseReasonComment, -- N/A for answers as close reasons are for questions, but included for UNION ALL compatibility
    Q.WasClosed AS WasClosed, -- Get close status from parent question
    Q.WasMigratedAway AS WasMigratedAway, -- Get migration status from parent question
    PLA.LinkedPostsCount,
    PLA.DuplicatePostsCount,
    PLA.MaxRelatedPostScore,
    TP.TagName AS MostPopularTagUsed,
    TP.TotalTagScore,
    TP.TagScoreRank,
    COALESCE(PLA.TotalBountyAmountOffered, 0) AS PostBounty,
    COALESCE(PLA.AvgCommenterReputation, 0.0) AS AvgCommenterReputationOnPost,
    CASE
        WHEN PDB.PostScore > 75 AND PDB.ParentId IS NOT NULL THEN 'Highly Upvoted Answer to a Question'
        WHEN PDB.PostScore BETWEEN 20 AND 75 AND Q.AcceptedAnswerId = PDB.PostId THEN 'Accepted Moderately Upvoted Answer'
        ELSE 'Other Notable Answer'
    END AS PostInfluenceCategory,
    EXTRACT(DAY FROM (NOW() - PDB.PostCreationDate)) AS DaysSincePostCreation,
    (
        SELECT COUNT(DISTINCT C.UserId)
        FROM Comments AS C
        WHERE C.PostId = PDB.PostId
        AND C.CreationDate > PDB.PostCreationDate
        AND C.UserId IS NOT NULL
        AND C.UserId != UCS.UserId
    ) AS UniqueCommentersOnPost,
    UCS.AvgCommentLength,
    UCS.AvgTimeBetweenPostsInSeconds,
    LENGTH(PDB.Body) AS BodyLength,
    NULL AS AnswerConversionRate -- N/A for answers
FROM UserContributionSummary AS UCS
INNER JOIN PostDetailsBase AS PDB ON UCS.UserId = PDB.OwnerUserId
LEFT JOIN PostLinkInfluence AS PLA ON PDB.PostId = PLA.PostId
LEFT JOIN PostDetailsBase AS Q ON PDB.ParentId = Q.PostId AND Q.PostTypeId = 1 -- Join to parent question for context
LEFT JOIN (
    SELECT DISTINCT ON (P.Id)
        P.Id,
        T.TagName,
        TP_CTE.TotalTagScore,
        TP_CTE.TagScoreRank
    FROM Posts AS P
    JOIN (SELECT Id, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS TagName FROM Posts WHERE Tags IS NOT NULL) AS PT ON P.Id = PT.Id
    JOIN TagPerformance AS TP_CTE ON PT.TagName = TP_CTE.TagName
    ORDER BY P.Id, TP_CTE.TotalTagScore DESC, TP_CTE.TagScoreRank ASC
) AS TP ON Q.PostId = TP.Id -- Get tag info from the parent question
WHERE
    PDB.PostTypeId = 2 -- Only answers
    AND UCS.TotalAnswers > 5 AND UCS.Reputation > 750 -- Higher bar for answerers
    AND PDB.PostScore > 5
    AND PDB.UserPostScoreRank <= 3 -- Top 3 answers by user score
    AND PDB.PostCreationDate >= '2023-01-01'
    AND PDB.PostCreationDate <= '2024-01-01'
    AND PDB.ParentId IS NOT NULL
    AND Q.PostId IS NOT NULL -- Ensure parent question exists and is in PostDetailsBase
    AND Q.Tags LIKE '%[Pp]ython%' -- Answers to Python questions
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory AS PH_INNER
        WHERE PH_INNER.PostId = PDB.PostId
        AND PH_INNER.PostHistoryTypeId = 12
        AND PH_INNER.CreationDate > PDB.CreationDate
    )
ORDER BY Reputation DESC, PostScore DESC, DaysSincePostCreation ASC
LIMIT 2000;
