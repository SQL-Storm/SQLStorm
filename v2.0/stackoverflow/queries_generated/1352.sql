-- {"query": "1352.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2741} 

WITH UserActivity AS (
    -- Calculate aggregated user activity metrics including post, comment counts, and total scores.
    -- This CTE focuses on capturing the overall engagement level of users.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        -- Find the latest interaction date across posts and comments, handling NULLs gracefully.
        MAX(GREATEST(COALESCE(P.LastActivityDate, '1900-01-01'), COALESCE(C.CreationDate, '1900-01-01'))) AS LastInteractionDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        U.Views AS UserProfileViews
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
PostDetailMetrics AS (
    -- Analyze individual posts for quality, popularity, and historical edits.
    -- Includes correlated subqueries and window functions for ranking.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        -- Extract and clean tags for easier processing. Handles cases where Tags might be NULL or empty.
        COALESCE(NULLIF(TRIM(REPLACE(REPLACE(P.Tags, '>', ''), '<', ' ')), ''), 'no-tag') AS CleanTags,
        -- Correlated subquery: count how many times this post is linked as a duplicate.
        (SELECT COUNT(PL_dup.Id) FROM PostLinks AS PL_dup WHERE PL_dup.RelatedPostId = P.Id AND PL_dup.LinkTypeId = 3) AS DuplicateLinkedCount,
        -- Correlated subquery: check if the post has been closed, and retrieve the primary close reason if available.
        (SELECT CR.Name FROM PostHistory AS PH_close JOIN CloseReasonTypes AS CR ON PH_close.Comment::smallint = CR.Id WHERE PH_close.PostId = P.Id AND PH_close.PostHistoryTypeId = 10 ORDER BY PH_close.CreationDate DESC LIMIT 1) AS PrimaryCloseReason,
        -- Window function: rank posts by score within their specific PostType.
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreInType,
        -- Get the most recent edit date from PostHistory for title, body, or tags.
        (SELECT MAX(PH.CreationDate) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS LastEditHistoryDate
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2) -- Only consider Questions (1) and Answers (2) for this analysis.
),
AggregatedTagStats AS (
    -- Calculate aggregated statistics for tags, identifying popular and high-scoring tags.
    -- Uses string functions to split the 'CleanTags' into individual tags.
    SELECT
        TRIM(tag_val) AS TagName,
        COUNT(DISTINCT PDM.PostId) AS TagPostCount,
        SUM(PDM.PostScore) AS TagTotalScore,
        AVG(PDM.PostScore) AS TagAvgScore,
        SUM(PDM.ViewCount) AS TagTotalViews,
        SUM(PDM.AnswerCount) AS TagTotalAnswers,
        SUM(PDM.CommentCount) AS TagTotalComments
    FROM PostDetailMetrics AS PDM
    -- PostgreSQL specific for splitting string into rows. Replace with appropriate function for other DBs.
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(PDM.CleanTags, ' ')) AS tag_val
    WHERE TRIM(tag_val) <> '' AND PDM.PostTypeId = 1 -- Only consider tags from questions
    GROUP BY TRIM(tag_val)
),
UserBadgeOverview AS (
    -- Summarize user badge achievements, including count of each badge class.
    -- Features a correlated subquery to find a specific badge detail.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        -- Correlated subquery: get the name of the most recent gold badge for the user.
        (SELECT Name FROM Badges WHERE UserId = B.UserId AND Class = 1 ORDER BY Date DESC LIMIT 1) AS MostRecentGoldBadgeName
    FROM Badges AS B
    GROUP BY B.UserId
),
PostCommentSentiment AS (
    -- Analyze comments associated with posts for potential sentiment or issue indicators.
    -- Uses string matching for simple sentiment detection.
    SELECT
        C.PostId,
        AVG(C.Score) AS AvgCommentScore,
        COUNT(CASE WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%appreciate%' THEN 1 END) AS PositiveCommentCount,
        COUNT(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' THEN 1 END) AS ProblematicCommentCount,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Comments AS C
    GROUP BY C.PostId
)
-- Main query: Combines all the pre-processed data to generate a comprehensive user profile analysis.
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.UserCreationDate,
    UA.TotalPosts,
    UA.QuestionCount,
    UA.AnswerCount,
    UA.TotalPostScore,
    UBO.GoldBadges,
    UBO.SilverBadges,
    UBO.BronzeBadges,
    UBO.MostRecentGoldBadgeName,
    UBO.LastBadgeDate,
    PDM_Q.PostId AS TopQuestionId,
    PDM_Q.PostScore AS TopQuestionScore,
    PDM_Q.ViewCount AS TopQuestionViews,
    PDM_Q.CleanTags AS TopQuestionTags,
    PDM_Q.DuplicateLinkedCount AS TopQuestionDuplicateLinks,
    PDM_Q.PrimaryCloseReason AS TopQuestionCloseReason,
    PCS_Q.AvgCommentScore AS TopQuestionAvgCommentScore,
    PCS_Q.ProblematicCommentCount AS TopQuestionProblematicComments,
    -- Non-correlated subquery for verification: count actual answers for the top question.
    (SELECT COUNT(P_child.Id) FROM Posts AS P_child WHERE P_child.ParentId = PDM_Q.PostId AND P_child.PostTypeId = 2) AS VerifiedTopQuestionAnswerCount,
    -- Complex calculation: a custom user engagement score based on various weighted metrics.
    (UA.TotalPostScore * 0.4 + UA.TotalCommentScore * 0.1 + UA.TotalPosts * 0.05 + UA.UserProfileViews * 0.005 + UBO.TotalBadges * 1.0 + UBO.GoldBadges * 5.0) AS UserEngagementScore,
    -- Window function: divide users into 10 engagement groups (deciles).
    NTILE(10) OVER (ORDER BY (UA.TotalPostScore * 0.4 + UA.TotalCommentScore * 0.1 + UA.TotalPosts * 0.05 + UA.UserProfileViews * 0.005 + UBO.TotalBadges * 1.0 + UBO.GoldBadges * 5.0) DESC) AS EngagementDecile,
    -- String expression and NULL logic: extract and uppercase the first 3 characters of user's location, default to 'UNKNOWN'.
    COALESCE(UPPER(SUBSTRING(U.Location, 1, 3)), 'UNKNOWN') AS LocationPrefix,
    -- NULL logic and complicated predicate: determine user activity status based on last interaction date.
    CASE
        WHEN UA.LastInteractionDate IS NULL OR UA.LastInteractionDate < '1900-01-02' THEN 'Never Interacted' -- Handle initial dummy date if no activity
        WHEN UA.LastInteractionDate > (CURRENT_TIMESTAMP - INTERVAL '30 days') THEN 'Highly Active'
        WHEN UA.LastInteractionDate > (CURRENT_TIMESTAMP - INTERVAL '90 days') THEN 'Active'
        WHEN UA.LastInteractionDate > (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN 'Moderately Active'
        ELSE 'Lapsed'
    END AS UserActivityStatus,
    ATS.TagName AS TopContributingTagName,
    ATS.TagTotalScore AS TopContributingTagTotalScore,
    ATS.TagAvgScore AS TopContributingTagAvgScore,
    -- Calculate days since last access/interaction
    EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, UA.UserLastAccessDate)) AS DaysSinceLastAccess,
    EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, UA.LastInteractionDate)) AS DaysSinceLastInteraction
FROM Users AS U
INNER JOIN UserActivity AS UA ON U.Id = UA.UserId
LEFT JOIN UserBadgeOverview AS UBO ON U.Id = UBO.UserId
-- Left join to get the user's top-scoring question.
LEFT JOIN PostDetailMetrics AS PDM_Q ON U.Id = PDM_Q.OwnerUserId AND PDM_Q.PostTypeId = 1 AND PDM_Q.RankByScoreInType = 1
-- Left join to get comment sentiment for the top question.
LEFT JOIN PostCommentSentiment AS PCS_Q ON PDM_Q.PostId = PCS_Q.PostId
-- Left join to find a "top contributing tag" for the user, based on their top question's tags and overall tag performance.
LEFT JOIN AggregatedTagStats AS ATS ON ATS.TagName IN (SELECT UNNEST(STRING_TO_ARRAY(PDM_Q.CleanTags, ' ')))
                                    AND ATS.TagPostCount > 50 AND ATS.TagAvgScore > 10 -- Only consider sufficiently popular and high-scoring tags
WHERE
    UA.Reputation > 1000 -- Filter for more established users
    AND UA.TotalPosts > 10 -- Users with a minimum number of posts
    AND UBO.TotalBadges IS NOT NULL -- Exclude users with no badges
    -- Correlated subquery: ensure the user has not recently edited any posts owned by a specific 'community' user (OwnerUserId = -1)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory AS PH_ce
        WHERE PH_ce.UserId = U.Id
          AND PH_ce.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '7 days')
          AND PH_ce.PostId IN (SELECT P_comm.Id FROM Posts AS P_comm WHERE P_comm.OwnerUserId = -1)
    )
ORDER BY
    UserEngagementScore DESC, UA.Reputation DESC, UA.LastInteractionDate DESC
LIMIT 5000;
