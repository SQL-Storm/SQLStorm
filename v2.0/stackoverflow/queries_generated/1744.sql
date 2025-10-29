-- {"query": "1744.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3642} 

WITH UserRelevantPosts AS (
    -- Combines various user-generated content (questions, answers, comments) into a single stream,
    -- applying initial date and type filters.
    SELECT
        P.Id AS EntityId,
        P.PostTypeId,
        P.OwnerUserId AS UserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        P.CommentCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Body,
        'Post' AS ActivityType,
        (CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END) AS IsCommunityOwned
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
      AND (P.PostTypeId = 1 OR P.PostTypeId = 2) -- Only Questions (1) and Answers (2)
      AND P.Body IS NOT NULL AND LENGTH(P.Body) > 50
    UNION ALL
    SELECT
        C.Id AS EntityId,
        99 AS PostTypeId, -- Custom type for comments
        C.UserId,
        C.CreationDate,
        C.Score,
        NULL AS ViewCount,
        NULL AS AcceptedAnswerId,
        C.PostId AS ParentId, -- Using ParentId to link to the associated post
        NULL AS Tags,
        NULL AS CommentCount,
        C.CreationDate AS LastActivityDate,
        NULL AS ClosedDate,
        C.Text AS Body, -- Comment text as body
        'Comment' AS ActivityType,
        FALSE AS IsCommunityOwned
    FROM Comments C
    WHERE C.UserId IS NOT NULL
      AND C.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
      AND LENGTH(C.Text) > 20 -- Filter out very short comments
),
UserActivitySummary AS (
    -- Aggregates core activity metrics for users from UserRelevantPosts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 THEN URP.EntityId END) AS QuestionsAsked,
        SUM(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 AND URP.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.EntityId END) AS AnswersGiven,
        SUM(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Comment' THEN URP.EntityId END) AS TotalCommentsMade,
        MAX(URP.LastActivityDate) AS LastUserOverallActivityDate
    FROM Users U
    INNER JOIN UserRelevantPosts URP ON U.Id = URP.UserId
    WHERE U.Reputation > 5000
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 THEN URP.EntityId END) >= 1 -- Users must have asked at least one question
),
UserOwnPostEditHistory AS (
    -- Summarizes edits made by users to their own posts, excluding community user edits.
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS OwnPostsEditedCount,
        MAX(PH.CreationDate) AS LastOwnPostEditDate,
        (EXTRACT(EPOCH FROM (MAX(PH.CreationDate) - MIN(PH.CreationDate))) / (60 * 60 * 24)) AS DaysBetweenFirstAndLastEdit
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId = P.OwnerUserId -- User edited their own post
      AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
      AND PH.UserId <> -1 -- Not edited by community user
      AND PH.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    GROUP BY PH.UserId
    HAVING COUNT(DISTINCT PH.PostId) >= 1
),
UserBadgeTimeSpans AS (
    -- Calculates the time span between a user's first and last Gold/Silver badge.
    SELECT
        B.UserId,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate,
        (EXTRACT(EPOCH FROM (MAX(B.Date) - MIN(B.Date))) / (60 * 60 * 24)) AS DaysSpanBetweenBadges
    FROM Badges B
    WHERE B.Class IN (1, 2) -- Gold (1) or Silver (2) badges only
      AND B.Date BETWEEN '2019-01-01' AND '2023-12-31'
    GROUP BY B.UserId
    HAVING COUNT(B.Id) >= 2 -- At least two badges to calculate a span
),
UserUpvotedOtherAnswers AS (
    -- Identifies users who have answered a question that was not their own and received an upvote.
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT A.Id) AS UpvotedOtherAnswersCount
    FROM Posts A
    INNER JOIN Posts Q ON A.ParentId = Q.Id AND A.OwnerUserId <> Q.OwnerUserId -- Answer to someone else's question
    INNER JOIN Votes V ON A.Id = V.PostId
    WHERE A.PostTypeId = 2 -- Is an answer
      AND V.VoteTypeId = 2 -- Is an upvote
      AND A.CreationDate > (CURRENT_DATE - INTERVAL '3 year') -- Recent answers
    GROUP BY A.OwnerUserId
    HAVING COUNT(DISTINCT A.Id) >= 1
),
UserRankedPosts AS (
    -- Ranks a user's posts by last activity and score, including LAG for comparison.
    SELECT
        URP.UserId,
        URP.EntityId AS PostId,
        URP.PostTypeId,
        URP.CreationDate AS PostCreationDate,
        URP.Score AS PostScore,
        URP.ViewCount,
        URP.Tags,
        URP.CommentCount,
        URP.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY URP.UserId ORDER BY URP.LastActivityDate DESC, URP.Score DESC) AS rn_post_activity,
        LAG(URP.Score, 1, 0) OVER (PARTITION BY URP.UserId ORDER BY URP.CreationDate) AS PreviousPostScore, -- LAG for sequential analysis
        COALESCE(URP.ClosedDate, '9999-12-31 23:59:59') AS EffectiveClosedDate -- NULL logic
    FROM UserRelevantPosts URP
    WHERE URP.ActivityType = 'Post' AND URP.ViewCount > 10 AND URP.Body IS NOT NULL
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsAsked,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.AnswersGiven,
    UAS.TotalAnswerScore,
    UAS.AvgAnswerScore,
    UAS.TotalCommentsMade,
    UOEH.OwnPostsEditedCount,
    UOEH.LastOwnPostEditDate,
    UOEH.DaysBetweenFirstAndLastEdit,
    UBTS.DaysSpanBetweenBadges,
    UUOA.UpvotedOtherAnswersCount,
    -- Correlated subquery to find the most active tag for a user's questions,
    -- considering tag usage count and total score for those tags.
    (
        SELECT T.TagName
        FROM Posts P_sub
        CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P_sub.Tags, 2, LENGTH(P_sub.Tags) - 2), '><')) AS tag_name_parsed
        JOIN Tags T ON T.TagName = tag_name_parsed
        WHERE P_sub.OwnerUserId = UAS.UserId
          AND P_sub.PostTypeId = 1 -- Only questions
          AND P_sub.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
        GROUP BY T.TagName
        ORDER BY COUNT(P_sub.Id) DESC, SUM(P_sub.Score) DESC, T.TagName ASC
        LIMIT 1
    ) AS MostActiveQuestionTag,
    -- Aggregates titles and scores of the user's top 3 most recent posts,
    -- demonstrating STRING_AGG and complex string formatting.
    STRING_AGG(DISTINCT URP.Title || ' (Score: ' || URP.PostScore || ')', '; ') WITHIN GROUP (ORDER BY URP.rn_post_activity) AS Top3RecentPostsTitles,
    SUM(CASE WHEN URP.PostTypeId = 1 AND URP.PostScore > URP.PreviousPostScore THEN 1 ELSE 0 END) AS QuestionsWithScoreIncrease,
    -- Categorizes users into tiers based on their reputation using CASE expression.
    CASE
        WHEN UAS.Reputation >= 200000 THEN 'Legendary Contributor'
        WHEN UAS.Reputation >= 50000 THEN 'Senior Contributor'
        WHEN UAS.Reputation >= 10000 THEN 'Mid-Level Contributor'
        ELSE 'Junior Contributor'
    END AS UserTier,
    -- Finds the latest closure date for any of the user's own posts that were closed as a duplicate (CloseReasonId 101).
    -- Includes NULL logic (COALESCE) and complicated predicate (`Comment LIKE '101%'`).
    COALESCE(MAX(CASE WHEN PH_Closed.PostHistoryTypeId = 10 AND PH_Closed.Comment LIKE '101%' THEN PH_Closed.CreationDate END), '1900-01-01 00:00:00') AS LastDuplicateClosureDateForOwnPosts,
    -- Non-correlated subquery to find the last time a user marked a post as favorite.
    (
        SELECT MAX(V.CreationDate)
        FROM Votes V
        WHERE V.UserId = UAS.UserId
          AND V.VoteTypeId = 5 -- Favorite (bookmark)
          AND V.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    ) AS LastFavoriteVoteDate,
    -- Calculates a composite activity score based on various weighted metrics.
    (UAS.Reputation / 1000.0) * 0.3 + (UAS.QuestionsAsked * 2.0) * 0.2 + (UAS.AnswersGiven * 1.5) * 0.15 + (UAS.TotalCommentsMade * 0.5) * 0.1 + (COALESCE(UOEH.OwnPostsEditedCount, 0) * 1.0) * 0.1
    + (COALESCE(UBTS.DaysSpanBetweenBadges, 0) / 365.0) * 0.05 + (COALESCE(UUOA.UpvotedOtherAnswersCount, 0) * 1.0) * 0.1 AS CompositeActivityScore
FROM UserActivitySummary UAS
LEFT JOIN UserOwnPostEditHistory UOEH ON UAS.UserId = UOEH.UserId
LEFT JOIN UserBadgeTimeSpans UBTS ON UAS.UserId = UBTS.UserId
INNER JOIN UserUpvotedOtherAnswers UUOA ON UAS.UserId = UUOA.UserId -- INNER JOIN implies user MUST meet this condition
LEFT JOIN UserRankedPosts URP ON UAS.UserId = URP.UserId AND URP.rn_post_activity <= 3 -- Joins top 3 ranked posts
LEFT JOIN PostHistory PH_Closed ON UAS.UserId = PH_Closed.UserId
    AND PH_Closed.PostId IN (SELECT EntityId FROM UserRelevantPosts WHERE UserId = UAS.UserId AND ActivityType = 'Post' AND PostTypeId = 1) -- Only consider user's own questions
    AND PH_Closed.PostHistoryTypeId = 10 -- Post Closed event
    AND PH_Closed.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
WHERE UAS.QuestionsWithAcceptedAnswer >= 1 -- At least one question with an accepted answer
  AND UAS.TotalCommentsMade >= 5 -- User has made at least 5 comments
  AND UOEH.OwnPostsEditedCount >= 1 -- User has edited their own posts at least once
  AND UBTS.DaysSpanBetweenBadges IS NOT NULL -- User must have a badge span (i.e., at least 2 Gold/Silver badges)
  AND UUOA.UpvotedOtherAnswersCount >= 1 -- User must have answered other users' questions that got upvoted
  -- Complex EXISTS subquery checking for specific criteria on user's questions:
  -- Must have a question with at least 5 comments, a body length > 500,
  -- created within 5 years of their registration, not marked as a duplicate in title,
  -- and linked to by other posts (LinkType 1).
  AND EXISTS (
        SELECT 1
        FROM UserRelevantPosts URP_crit
        WHERE URP_crit.UserId = UAS.UserId
          AND URP_crit.PostTypeId = 1 -- Is a question
          AND URP_crit.CommentCount >= 5
          AND LENGTH(URP_crit.Body) > 500
          AND URP_crit.CreationDate BETWEEN UAS.UserCreationDate AND (UAS.UserCreationDate + INTERVAL '5 years') -- Date range expression
          AND NOT URP_crit.Title ILIKE '%[duplicate]%' -- String expression, case-insensitive
          AND URP_crit.IsCommunityOwned = FALSE -- Not community owned
          AND URP_crit.EntityId IN (
                SELECT PL.PostId
                FROM PostLinks PL
                WHERE PL.RelatedPostId = URP_crit.EntityId AND PL.LinkTypeId = 1 -- Post has links to it
            )
    )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsAsked,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.AnswersGiven,
    UAS.TotalAnswerScore,
    UAS.AvgAnswerScore,
    UAS.TotalCommentsMade,
    UOEH.OwnPostsEditedCount,
    UOEH.LastOwnPostEditDate,
    UOEH.DaysBetweenFirstAndLastEdit,
    UBTS.DaysSpanBetweenBadges,
    UUOA.UpvotedOtherAnswersCount
ORDER BY
    CompositeActivityScore DESC,
    UAS.Reputation DESC,
    UBTS.DaysSpanBetweenBadges DESC,
    UAS.LastUserOverallActivityDate DESC
LIMIT 1000;
