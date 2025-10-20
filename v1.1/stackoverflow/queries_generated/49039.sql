-- {"query": "49039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2907} 

WITH PopularTags AS (
    -- Identify the top 50 most frequently used and non-moderator-only tags.
    -- This CTE helps focus the subsequent analysis on relevant technology areas.
    SELECT
        T.Id AS TagId,
        T.TagName
    FROM
        Tags T
    WHERE
        T.IsModeratorOnly = FALSE AND T.IsRequired = FALSE
    ORDER BY
        T.Count DESC
    LIMIT 50
),
CoreQuestions AS (
    -- Select high-impact questions (PostTypeId = 1) created within the last 3 years
    -- that have significant views, score, and are associated with at least one popular tag.
    -- Tags are parsed from the string format into an array for efficient matching.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><') AS QuestionTagsArray
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 -- PostType: Question
        AND P.CreationDate >= (NOW() - INTERVAL '3 years')
        AND P.ViewCount > 5000 -- Focus on highly viewed questions
        AND P.Score > 10 -- Focus on well-received questions
        AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure valid tags exist
        AND EXISTS (
            -- Ensure at least one tag from PopularTags is present in the question's tags
            SELECT 1
            FROM PopularTags PT
            WHERE PT.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))
        )
),
QuestionTagMapping AS (
    -- Explode the `QuestionTagsArray` into individual rows, linking questions to their popular tags.
    -- This facilitates tag-specific aggregations and analysis.
    SELECT
        CQ.QuestionId,
        CQ.OwnerUserId,
        T.Id AS TagId,
        T.TagName
    FROM
        CoreQuestions CQ,
        UNNEST(CQ.QuestionTagsArray) AS QuestionTag -- PostgreSQL's UNNEST to flatten the array
    INNER JOIN Tags T ON T.TagName = QuestionTag
    WHERE T.Id IN (SELECT TagId FROM PopularTags) -- Restrict to only the popular tags identified
),
RelevantAnswers AS (
    -- Identify answers (PostTypeId = 2) linked to the `CoreQuestions`.
    -- Calculate their scores, acceptance status, and count of comments.
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        COUNT(C.Id) AS CommentCountOnAnswer,
        CASE WHEN CQ.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM
        Posts A
    INNER JOIN CoreQuestions CQ ON A.ParentId = CQ.QuestionId
    LEFT JOIN Comments C ON A.Id = C.PostId
    WHERE
        A.PostTypeId = 2 -- PostType: Answer
        AND A.OwnerUserId IS NOT NULL -- Exclude posts owned by the community user or without owner
    GROUP BY
        A.Id, A.ParentId, A.OwnerUserId, A.Score, A.CreationDate, CQ.AcceptedAnswerId
),
UserPostAggregates AS (
    -- Aggregate key metrics for each user based on their contributions to CoreQuestions and RelevantAnswers.
    -- This includes total questions/answers, cumulative scores, view counts, and acceptance rates.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.UpVotes AS UserReceivedUpVotes, -- Upvotes received by the user on all their content
        U.DownVotes AS UserReceivedDownVotes, -- Downvotes received by the user on all their content
        COUNT(DISTINCT CQ.QuestionId) AS TotalQuestionsAsked,
        SUM(CQ.QuestionScore) AS TotalQuestionScore,
        SUM(CQ.ViewCount) AS TotalQuestionViews,
        SUM(CQ.FavoriteCount) AS TotalQuestionFavorites,
        COUNT(DISTINCT RA.AnswerId) AS TotalAnswersProvided,
        SUM(RA.AnswerScore) AS TotalAnswerScore,
        SUM(RA.IsAcceptedAnswer) AS TotalAcceptedAnswers,
        SUM(RA.CommentCountOnAnswer) AS TotalCommentsOnAnswers,
        -- Calculate average scores using conditional aggregation (FILTER clause)
        AVG(CQ.QuestionScore) FILTER (WHERE CQ.QuestionId IS NOT NULL) AS AvgQuestionScore,
        AVG(RA.AnswerScore) FILTER (WHERE RA.AnswerId IS NOT NULL) AS AvgAnswerScore
    FROM
        Users U
    LEFT JOIN CoreQuestions CQ ON U.Id = CQ.OwnerUserId
    LEFT JOIN RelevantAnswers RA ON U.Id = RA.AnswerOwnerUserId
    WHERE U.Id IS NOT NULL
    GROUP BY
        U.Id, U.Reputation, U.UpVotes, U.DownVotes
    HAVING
        COUNT(DISTINCT CQ.QuestionId) > 0 OR COUNT(DISTINCT RA.AnswerId) > 0 -- Only include users with at least one core post
),
UserBadgeStats AS (
    -- Count Gold and Silver badges for users, with a specific focus on tag-based badges
    -- that are directly related to the `PopularTags` identified earlier.
    SELECT
        B.UserId,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 1 AND B.TagBased = TRUE AND EXISTS (
            SELECT 1 FROM PopularTags PT JOIN Tags T ON PT.TagId = T.Id WHERE T.TagName = B.Name
        )) AS GoldTagBadgesForPopularTags,
        COUNT(B.Id) FILTER (WHERE B.Class = 2 AND B.TagBased = TRUE AND EXISTS (
            SELECT 1 FROM PopularTags PT JOIN Tags T ON PT.TagId = T.Id WHERE T.TagName = B.Name
        )) AS SilverTagBadgesForPopularTags
    FROM
        Badges B
    WHERE
        B.UserId IN (SELECT UserId FROM UserPostAggregates) -- Only consider badges for active users
    GROUP BY
        B.UserId
),
UserPostHistoryEvents AS (
    -- Count specific post history events for posts owned by the user,
    -- indicating user engagement in post lifecycle management (e.g., editing, closing, reopening).
    SELECT
        PH.UserId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10) AS PostsClosedByOthersCount, -- Post Closed by others or user (if voter)
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS PostsReopenedCount, -- Post Reopened
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 12) AS PostsDeletedCount, -- Post Deleted
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 13) AS PostsUndeletedCount, -- Post Undeleted
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS UserEditCount -- Edit Title, Body, Tags by this user
    FROM
        PostHistory PH
    WHERE
        PH.PostId IN (SELECT QuestionId FROM CoreQuestions UNION ALL SELECT AnswerId FROM RelevantAnswers)
        AND PH.UserId IS NOT NULL -- Exclude community/system actions
        AND PH.UserId IN (SELECT UserId FROM UserPostAggregates)
    GROUP BY
        PH.UserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.Views AS UserProfileViews,
    U.UpVotes AS UserGivenUpVotes, -- Upvotes given by this user
    U.DownVotes AS UserGivenDownVotes, -- Downvotes given by this user
    UPA.TotalQuestionsAsked,
    UPA.TotalAnswersProvided,
    UPA.TotalQuestionScore,
    UPA.TotalAnswerScore,
    UPA.TotalAcceptedAnswers,
    UPA.TotalQuestionViews,
    UPA.TotalQuestionFavorites,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesReceived,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesReceived,
    COALESCE(UBS.GoldTagBadgesForPopularTags, 0) AS GoldTagBadgesOnPopularTags,
    COALESCE(UBS.SilverTagBadgesForPopularTags, 0) AS SilverTagBadgesOnPopularTags,
    COALESCE(UPHE.PostsClosedByOthersCount, 0) AS UserRelatedPostsClosed,
    COALESCE(UPHE.PostsReopenedCount, 0) AS UserRelatedPostsReopened,
    COALESCE(UPHE.PostsDeletedCount, 0) AS UserRelatedPostsDeleted,
    COALESCE(UPHE.PostsUndeletedCount, 0) AS UserRelatedPostsUndeleted,
    COALESCE(UPHE.UserEditCount, 0) AS UserInitiatedEdits,
    UPA.AvgQuestionScore,
    UPA.AvgAnswerScore,
    -- A composite "User Impact Score" calculated using weighted sum of various metrics.
    -- This score attempts to quantify a user's overall positive contribution and influence.
    (
        U.Reputation * 0.4 +                          -- Base reputation
        UPA.TotalQuestionScore * 0.2 +                -- Score from questions
        UPA.TotalAnswerScore * 0.3 +                  -- Score from answers
        UPA.TotalAcceptedAnswers * 7 +                -- High value for accepted answers
        UPA.TotalQuestionFavorites * 0.1 +            -- Questions favorited
        COALESCE(UBS.GoldBadges, 0) * 12 +            -- Value of Gold badges
        COALESCE(UBS.SilverBadges, 0) * 4 +           -- Value of Silver badges
        COALESCE(UBS.GoldTagBadgesForPopularTags, 0) * 18 + -- Higher value for specific tag Gold badges
        COALESCE(UBS.SilverTagBadgesForPopularTags, 0) * 6 + -- Higher value for specific tag Silver badges
        COALESCE(UPHE.PostsReopenedCount, 0) * 8 -    -- Positive: Reopening implies improvement
        COALESCE(UPHE.PostsClosedByOthersCount, 0) * 4 + -- Negative: Posts being closed
        COALESCE(UPHE.PostsUndeletedCount, 0) * 5 +   -- Positive: Undeleting posts
        COALESCE(UPHE.UserInitiatedEdits, 0) * 0.7    -- Value of active editing for improvement
    ) AS UserImpactScore,
    -- Rank users based on their overall reputation and accepted answers, reflecting general authority.
    RANK() OVER (ORDER BY U.Reputation DESC, UPA.TotalAcceptedAnswers DESC, (UPA.TotalQuestionScore + UPA.TotalAnswerScore) DESC) AS OverallUserRank,
    -- Rank users specifically based on their engagement with popular tags (badges) and answer acceptance,
    -- indicating domain-specific expertise.
    DENSE_RANK() OVER (ORDER BY (
        COALESCE(UBS.GoldTagBadgesForPopularTags, 0) * 2.0 + COALESCE(UBS.SilverTagBadgesForPopularTags, 0) * 1.0
    ) DESC, UPA.TotalAcceptedAnswers DESC, UPA.TotalAnswerScore DESC) AS TagEngagementRank
FROM
    Users U
INNER JOIN UserPostAggregates UPA ON U.Id = UPA.UserId
LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
LEFT JOIN UserPostHistoryEvents UPHE ON U.Id = UPHE.UserId
WHERE
    U.Reputation > 10000 -- Focus on highly reputable users for this analysis
    AND (COALESCE(UPA.TotalQuestionsAsked, 0) + COALESCE(UPA.TotalAnswersProvided, 0)) > 20 -- Ensure significant activity
ORDER BY
    UserImpactScore DESC, U.Reputation DESC
LIMIT 500; -- Limit the output to the top 500 users for benchmarking purposes
