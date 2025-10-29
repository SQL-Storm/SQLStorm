-- {"query": "1597.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3576} 

WITH UserEngagement AS (
    -- CTE 1: Summarize core user engagement metrics, activity, and reputation density.
    -- Includes flags for editing behavior and self-moderation (closing/deleting own posts).
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        U.CreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT Q.Id) FILTER (WHERE Q.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT A.Id) FILTER (WHERE A.PostTypeId = 2) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalPostFavorites,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Complex calculation: Reputation gain per day since creation
        CAST(U.Reputation AS numeric) / NULLIF(EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60 * 60 * 24), 0) AS ReputationPerDay,
        -- Check if the user has ever edited any post (PostHistoryTypeId: 4=Edit Title, 5=Edit Body, 6=Edit Tags)
        MAX(CASE WHEN PH_User.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS HasEditedPosts,
        -- Check if the user has ever closed or deleted their own post (PostHistoryTypeId: 10=Post Closed, 12=Post Deleted)
        MAX(CASE WHEN PH_User.PostHistoryTypeId IN (10,12) THEN 1 ELSE 0 END) AS HasClosedOrDeletedOwnPost
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Comments C ON U.Id = C.UserId
    -- Join PostHistory to see actions performed BY the user, not necessarily on their own posts
    LEFT JOIN PostHistory PH_User ON U.Id = PH_User.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
UserBadgeCounts AS (
    -- CTE 2: Aggregate badge counts for each user by class (Gold, Silver, Bronze).
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM Badges B
    GROUP BY B.UserId
),
RelevantTags AS (
    -- CTE 3: Defines a set of 'tech' related tags to filter posts.
    SELECT DISTINCT TagName
    FROM Tags
    WHERE TagName ILIKE '%sql%'
       OR TagName ILIKE '%python%'
       OR TagName ILIKE '%java%'
       OR TagName ILIKE '%javascript%'
       OR TagName ILIKE '%c#%'
       OR TagName ILIKE '%azure%'
       OR TagName ILIKE '%aws%'
       OR TagName ILIKE '%docker%'
       OR TagName ILIKE '%kubernetes%'
       OR TagName ILIKE '%react%'
       OR TagName ILIKE '%angular%'
       OR TagName ILIKE '%linux%'
       OR TagName ILIKE '%windows-server%'
       OR TagName ILIKE '%database%'
),
PostQualityMetrics AS (
    -- CTE 4: Calculates detailed quality and activity metrics for individual posts.
    -- Includes window functions for ranking answers and correlated subqueries for specific user/editor data.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount AS PostAnswerCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.ParentId,
        P.AcceptedAnswerId,
        P.Tags,
        P.Title,
        P.ClosedDate,
        P.Body,
        P.LastEditorUserId,
        COUNT(DISTINCT CO.Id) AS CommentCountOnPost,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnPost, -- UpMod
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnPost, -- DownMod
        MAX(CASE WHEN PH_Post.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS WasEdited,
        MAX(CASE WHEN PH_Post.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH_Post.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        -- Check if the post was specifically closed as a 'Duplicate'
        MAX(CASE WHEN PH_Post.PostHistoryTypeId = 10 AND CR.Name = 'Duplicate' THEN 1 ELSE 0 END) AS WasClosedAsDuplicate,
        -- Window function: Ranks answers for a specific question based on their score and creation date.
        ROW_NUMBER() OVER (PARTITION BY P.ParentId ORDER BY P.Score DESC, P.CreationDate ASC) AS AnswerScoreRank,
        -- Correlated subquery: Checks if the post owner has any Gold badges.
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = P.OwnerUserId AND B.Class = 1) AS OwnerHasGoldBadge,
        -- Correlated subquery: Retrieves the reputation of the last editor of the post.
        (SELECT U.Reputation FROM Users U WHERE U.Id = P.LastEditorUserId) AS LastEditorReputation,
        -- String expression/calculation: Estimates the density of the word 'code' in the post body.
        CAST(LENGTH(P.Body) - LENGTH(REPLACE(LOWER(P.Body), 'code', '')) AS NUMERIC) / NULLIF(LENGTH('code'),0) / NULLIF(LENGTH(P.Body), 0) AS CodeKeywordDensity
    FROM Posts P
    LEFT JOIN Comments CO ON P.Id = CO.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    -- Join PostHistory to see events related TO the post
    LEFT JOIN PostHistory PH_Post ON P.Id = PH_Post.PostId
    -- Join CloseReasonTypes based on PostHistory comment field, assuming it's the ID as varchar
    LEFT JOIN CloseReasonTypes CR ON PH_Post.PostHistoryTypeId = 10 AND PH_Post.Comment = CR.Id::varchar
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.ParentId, P.AcceptedAnswerId, P.Tags, P.Title, P.ClosedDate, P.Body, P.LastEditorUserId
),
CommunityImpact AS (
    -- CTE 5: Links questions to their answers and computes an "engagement score" for answers.
    SELECT
        Q.PostId AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.PostCreationDate AS QuestionCreationDate,
        Q.PostScore AS QuestionScore,
        Q.PostViewCount AS QuestionViewCount,
        Q.PostAnswerCount AS QuestionAnswerCount,
        Q.CommentCountOnPost AS QuestionCommentCount,
        Q.Tags AS QuestionTags,
        Q.Title AS QuestionTitle,
        A.PostId AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.PostCreationDate AS AnswerCreationDate,
        A.PostScore AS AnswerScore,
        A.CommentCountOnPost AS AnswerCommentCount,
        A.UpVotesOnPost AS AnswerUpVotes,
        A.DownVotesOnPost AS AnswerDownVotes,
        A.AnswerScoreRank,
        Q.AcceptedAnswerId = A.PostId AS IsAcceptedAnswer,
        -- Complex calculation: Answer engagement score
        (A.PostScore * 10 + A.AnswerCommentCount * 5 - A.DownVotesOnPost * 2 + (CASE WHEN Q.AcceptedAnswerId = A.PostId THEN 50 ELSE 0 END)) AS AnswerEngagementScore,
        -- NULL logic: Default to 0 if the last editor reputation is NULL
        COALESCE(A.LastEditorReputation, 0) AS AnswerLastEditorReputation,
        -- String expression/predicate: Checks if the question title implies a 'problem'
        (CASE WHEN Q.Title ILIKE '%issue%' OR Q.Title ILIKE '%problem%' THEN 1 ELSE 0 END) AS IsProblemQuestion,
        -- Check for existence of a 'Duplicate' link type for the question
        EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = Q.PostId AND PL.LinkTypeId = 3) AS HasDuplicateLink
    FROM PostQualityMetrics Q
    INNER JOIN PostQualityMetrics A ON Q.PostId = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
      AND Q.PostScore > 0
      AND A.PostScore >= 0
      AND Q.PostViewCount > 100
      AND Q.PostAnswerCount > 0
)
-- Main Query: Identifies influential tech contributors based on their high-quality, accepted answers
-- to relevant questions, considering their overall activity, reputation, and editing habits.
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationPerDay,
    COALESCE(UBC.GoldBadgesCount, 0) AS GoldBadgesCount,
    COALESCE(UBC.SilverBadgesCount, 0) AS SilverBadgesCount,
    COALESCE(UBC.BronzeBadgesCount, 0) AS BronzeBadgesCount,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    UE.HasEditedPosts,
    UE.HasClosedOrDeletedOwnPost,
    CI.QuestionId,
    CI.QuestionTitle,
    CI.QuestionScore,
    CI.QuestionViewCount,
    CI.QuestionCommentCount,
    CI.QuestionTags,
    CI.AnswerId,
    CI.AnswerScore,
    CI.AnswerCommentCount,
    CI.AnswerUpVotes,
    CI.AnswerDownVotes,
    CI.IsAcceptedAnswer,
    CI.AnswerEngagementScore,
    CI.AnswerLastEditorReputation,
    CI.IsProblemQuestion,
    CI.HasDuplicateLink,
    PQM.CodeKeywordDensity AS QuestionCodeKeywordDensity,
    -- Window function: Ranks users by their average answer engagement score within their creation year, handling NULLs.
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UE.CreationDate) ORDER BY AVG(CI.AnswerEngagementScore) DESC NULLS LAST) AS UserAvgAnswerEngagementRank
FROM UserEngagement UE
LEFT JOIN UserBadgeCounts UBC ON UE.UserId = UBC.UserId -- Outer join for badge counts (users without badges still included)
INNER JOIN CommunityImpact CI ON UE.UserId = CI.AnswerOwnerId -- Focus on users who provide answers
INNER JOIN PostQualityMetrics PQM ON CI.QuestionId = PQM.PostId -- Re-join for question-specific quality metrics
WHERE
    CI.QuestionCreationDate BETWEEN '2022-01-01' AND '2023-12-31' -- Filter for a recent activity window
    AND CI.IsAcceptedAnswer = TRUE -- Crucial: only accepted answers
    AND UE.UserProfileViews > 100 -- Users with some level of profile visibility
    -- Correlated subquery with NULL logic: Ensure the answer has never received an 'Offensive' vote from a user.
    AND NOT EXISTS (
        SELECT 1
        FROM Votes V_inner
        WHERE V_inner.PostId = CI.AnswerId
          AND V_inner.VoteTypeId = 4 -- Offensive vote type
          AND V_inner.UserId IS NOT NULL -- Anonymously cast offensive votes are not counted
    )
    -- Complex predicate: Users must have substantial post count AND either high total post score OR at least one accepted answer on their own posts.
    AND (UE.TotalPosts > 50 AND (UE.TotalPostScore > 500 OR EXISTS (SELECT 1 FROM Posts P_inner WHERE P_inner.OwnerUserId = UE.UserId AND P_inner.Id = P_inner.AcceptedAnswerId)))
    AND UE.ReputationPerDay > 0.5 -- Filter for actively growing users
    AND UE.HasEditedPosts = 1 -- Users who actively maintain posts
    -- String expression & predicate: Check if question tags intersect with predefined relevant tech tags.
    AND EXISTS (
        SELECT 1
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(CI.QuestionTags, 2, LENGTH(CI.QuestionTags)-2), '><')) AS tag_name -- Deconstructs the tags string
        INNER JOIN RelevantTags RT ON LOWER(tag_name) LIKE '%' || LOWER(RT.TagName) || '%'
    )
    AND CI.AnswerScoreRank = 1 -- Only consider the highest-scoring answer for each question
    AND CI.AnswerEngagementScore > 100 -- High engagement score for the answer
    AND PQM.CodeKeywordDensity IS NOT NULL AND PQM.CodeKeywordDensity > 0.001 -- Question body contains 'code' with reasonable density
    AND NOT PQM.WasClosed -- Only consider open questions
    AND PQM.WasClosedAsDuplicate = 0 -- Exclude questions that were explicitly closed as duplicates
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.ReputationPerDay, UBC.GoldBadgesCount, UBC.SilverBadgesCount, UBC.BronzeBadgesCount,
    UE.TotalQuestions, UE.TotalAnswers, UE.TotalPostScore, UE.HasEditedPosts, UE.HasClosedOrDeletedOwnPost, UE.CreationDate,
    CI.QuestionId, CI.QuestionTitle, CI.QuestionScore, CI.QuestionViewCount, CI.QuestionCommentCount,
    CI.QuestionTags, CI.AnswerId, CI.AnswerScore, CI.AnswerCommentCount, CI.AnswerUpVotes,
    CI.AnswerDownVotes, CI.IsAcceptedAnswer, CI.AnswerEngagementScore, CI.AnswerLastEditorReputation,
    CI.IsProblemQuestion, CI.HasDuplicateLink, PQM.CodeKeywordDensity, PQM.WasClosedAsDuplicate
HAVING
    COUNT(DISTINCT CI.AnswerId) > 1 -- Users must have provided more than one qualifying accepted answer
    AND AVG(CI.AnswerEngagementScore) > 150 -- Average engagement score for their answers is high
ORDER BY
    UserAvgAnswerEngagementRank ASC,
    UE.Reputation DESC,
    AVG(CI.AnswerEngagementScore) DESC
LIMIT 100;
