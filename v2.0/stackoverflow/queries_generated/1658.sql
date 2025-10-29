-- {"query": "1658.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2526} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity, reputation, and badge counts
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User #' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        MAX(P.CreationDate) AS LastPostActivityDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        AVG(CAST(P.Score AS NUMERIC)) AS AvgPostScoreOwned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges AS B ON U.Id = B.UserId
    WHERE
        U.Reputation > 750 -- Filter for reasonably reputable users
        AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Active in the last year
        AND U.Views > 50 -- Some profile visibility
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views
),
PostHistoryMetrics AS (
    -- CTE 2: Summarizes historical changes for posts
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS FirstClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeletedEver,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS WasUndeletedEver,
        STRING_AGG(DISTINCT CLR.Name, '; ') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS CloseReasonDetails
    FROM
        PostHistory AS PH
    LEFT JOIN
        CloseReasonTypes AS CLR ON PH.PostHistoryTypeId = 10 AND CLR.Id = CAST(PH.Comment AS SMALLINT) -- Correlate close reason text
    GROUP BY
        PH.PostId
),
RecentHighImpactPosts AS (
    -- CTE 3: Identifies high-impact questions and answers, combining them with UNION ALL
    -- High impact questions: high score, many answers, recent
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS PostOwnerId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.Title AS PostTitle,
        P.Tags AS PostTags,
        'Question' AS PostType,
        P.AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.AcceptedAnswerId,
        (SELECT COUNT(C.Id) FROM Comments AS C WHERE C.PostId = P.Id) AS CommentCountForPost,
        NULL AS AnswerToQuestionId,
        NULL AS ParentQuestionScore
    FROM
        Posts AS P
    WHERE
        P.PostTypeId = 1
        AND P.Score > 75 -- Only highly upvoted questions
        AND P.AnswerCount > 3 -- Questions with a good number of answers
        AND P.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '4 years' -- Created in the last 4 years
    UNION ALL
    -- High impact answers: high score, to a highly viewed question, recent
    SELECT
        A.Id AS PostId,
        A.OwnerUserId AS PostOwnerId,
        A.CreationDate AS PostCreationDate,
        A.Score AS PostScore,
        NULL AS PostViewCount, -- Answers don't have direct view counts
        NULL AS PostTitle,     -- Answers don't have titles
        NULL AS PostTags,      -- Answers don't have tags
        'Answer' AS PostType,
        NULL AS AnswerCount,   -- Answers don't have answer counts
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = A.Id AND V.VoteTypeId = 5) AS FavoriteCount, -- Favorite count for answers
        A.ParentId AS AcceptedAnswerId, -- Using ParentId here to link back to the question if it was the accepted answer
        (SELECT COUNT(C.Id) FROM Comments AS C WHERE C.PostId = A.Id) AS CommentCountForPost,
        A.ParentId AS AnswerToQuestionId,
        Q.Score AS ParentQuestionScore
    FROM
        Posts AS A
    INNER JOIN
        Posts AS Q ON A.ParentId = Q.Id
    WHERE
        A.PostTypeId = 2
        AND A.Score > 40 -- Highly upvoted answers
        AND Q.ViewCount > 25000 -- To questions with significant views
        AND A.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '4 years'
)
SELECT
    UE.UserId,
    UE.UserDisplayName,
    UE.Reputation,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.AvgPostScoreOwned,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.LastPostActivityDate,
    RHIP.PostId,
    RHIP.PostType,
    RHIP.PostTitle,
    RHIP.PostScore AS CurrentPostScore,
    RHIP.PostViewCount,
    RHIP.PostCreationDate,
    RHIP.AnswerCount AS QuestionAnswerCount,
    RHIP.FavoriteCount AS PostFavoriteCount,
    RHIP.CommentCountForPost,
    COALESCE(PHM.TotalHistoryEntries, 0) AS PostTotalHistoryEntries,
    COALESCE(PHM.EditCount, 0) AS PostEditCount,
    PHM.LastHistoryDate AS PostLastEditDate,
    PHM.FirstClosedDate,
    PHM.LastReopenedDate,
    PHM.WasDeletedEver,
    PHM.WasUndeletedEver,
    PHM.CloseReasonDetails,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostScore DESC, RHIP.PostCreationDate DESC) AS UserPostRankByScore,
    LEAD(RHIP.PostCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate) AS NextPostCreationDate,
    LAG(RHIP.PostCreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate) AS PreviousPostCreationDate,
    DATE_PART('day', RHIP.PostCreationDate - LAG(RHIP.PostCreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate)) AS DaysSincePrevPost,
    STRING_AGG(DISTINCT T.TagName, ', ') FILTER (WHERE T.TagName IS NOT NULL) AS AssociatedTags, -- Aggregates parsed tags
    (
        SELECT
            COUNT(DISTINCT PL.RelatedPostId)
        FROM
            PostLinks AS PL
        WHERE
            PL.PostId = RHIP.PostId
            AND PL.LinkTypeId = 3 -- LinkType 3 = Duplicate
    ) AS DuplicateCount,
    NULLIF(RHIP.PostScore, 0) / NULLIF(RHIP.PostViewCount, 0) AS ScorePerViewRatio, -- Prevents division by zero
    CASE
        WHEN RHIP.PostType = 'Question' AND RHIP.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answered Question'
        WHEN RHIP.PostType = 'Question' AND PHM.FirstClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN RHIP.PostType = 'Answer' AND RHIP.PostScore > 100 THEN 'Highly Voted Answer'
        WHEN RHIP.PostType = 'Answer' AND RHIP.ParentQuestionScore > 200 THEN 'Answer To Very Popular Question'
        ELSE 'Other High Impact Post'
    END AS PostStatusCategory,
    DATE_PART('day', CURRENT_TIMESTAMP - RHIP.PostCreationDate) AS DaysSincePostCreation,
    COALESCE(U.Location, 'Unknown') AS UserLocation_COALESCE,
    NULLIF(UE.TotalQuestionsOwned + UE.TotalAnswersOwned, 0) AS TotalContributionsForUser
FROM
    UserEngagement AS UE
INNER JOIN
    RecentHighImpactPosts AS RHIP ON UE.UserId = RHIP.PostOwnerId
LEFT JOIN
    PostHistoryMetrics AS PHM ON RHIP.PostId = PHM.PostId
LEFT JOIN LATERAL
    UNNEST(string_to_array(SUBSTRING(RHIP.PostTags, 2, LENGTH(RHIP.PostTags) - 2), '><')) AS PostTag(TagName) -- Parses tags string into individual rows (PostgreSQL specific)
LEFT JOIN
    Tags AS T ON LOWER(PostTag.TagName) = LOWER(T.TagName) -- Joins to Tags table for tag details
LEFT JOIN
    Users AS U ON UE.UserId = U.Id -- Re-join Users for Location, etc.
WHERE
    (PHM.WasDeletedEver = 0 OR PHM.WasDeletedEver IS NULL) -- Exclude posts that were deleted
    AND RHIP.PostScore >= (SELECT AVG(PostScore) FROM RecentHighImpactPosts WHERE PostType = RHIP.PostType) * 1.25 -- Post score must be 25% above its type's average
    AND UE.TotalPostsOwned > 5 -- Users with more than 5 total posts
    AND (RHIP.PostTitle IS NOT NULL OR RHIP.PostType = 'Answer') -- Ensure titles for questions
    AND RHIP.PostCreationDate BETWEEN UE.UserCreationDate AND CURRENT_TIMESTAMP -- Post creation date after user creation
    AND (PHM.FirstClosedDate IS NULL OR PHM.LastReopenedDate IS NOT NULL) -- Only include posts not closed, or closed and then reopened
ORDER BY
    UE.Reputation DESC,
    UE.UserId,
    UserPostRankByScore DESC;
