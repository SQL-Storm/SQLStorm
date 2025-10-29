-- {"query": "1713.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3050} 
WITH UserActivityMetrics AS (
    -- CTE 1: Aggregates comprehensive user activity details, including post counts, score summaries, and vote statistics.
    -- Incorporates date calculations, conditional aggregations, and a correlated subquery for distinct tag counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS UserViews,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswersPosted,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        MAX(COALESCE(p.LastActivityDate, p.CreationDate)) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentActivityDate,
        MAX(u.LastAccessDate) AS LastUserAccessDate,
        -- Calculate the average score for all posts created by the user, handling potential division by zero.
        ROUND(CAST(COALESCE(SUM(p.Score), 0) AS NUMERIC) / NULLIF(COUNT(DISTINCT p.Id), 0), 2) AS AverageScorePerPost,
        -- Correlated subquery: Count the number of distinct tags used by questions owned by this user.
        (SELECT COUNT(DISTINCT tag_val)
         FROM Posts sqp, UNNEST(string_to_array(SUBSTRING(sqp.Tags, 2, LENGTH(sqp.Tags) - 2), '><')) AS tag_val
         WHERE sqp.OwnerUserId = u.Id AND sqp.PostTypeId = 1 AND sqp.Tags IS NOT NULL
        ) AS DistinctQuestionTagsCount,
        -- Calculate the age of the user account in days.
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views, u.Location
),
PostDetailAnalysis AS (
    -- CTE 2: Performs detailed analysis on posts, including edit history, close reasons, linked/duplicate posts,
    -- and applies window functions for ranking. Also includes string processing for tags and complex calculations.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        -- Count specific types of post history events to derive an "EditCount".
        COUNT(ph_edit.Id) AS EditCount,
        -- Determine the latest close reason for the post, if any, using PostHistory and CloseReasonTypes.
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN crt.Name ELSE NULL END) AS LatestCloseReason,
        -- Count how many other posts this post links to (LinkTypeId = 1).
        COUNT(DISTINCT pl_linked.RelatedPostId) AS LinkedPostCount,
        -- Count how many other posts this post is a duplicate of (LinkTypeId = 3).
        COUNT(DISTINCT pl_duplicate.RelatedPostId) AS DuplicatePostCount,
        -- Correlated subquery: Calculate the average score of all answers associated with this question.
        (SELECT AVG(ans.Score)
         FROM Posts ans
         WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2) AS AverageAnswerScore,
        -- Window function: Rank posts by score within each PostTypeId.
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS PostScoreRankWithinType,
        -- Check if the post title contains specific keywords (e.g., 'sql', 'python'), case-insensitive.
        (LOWER(p.Title) LIKE '%sql%' ESCAPE '\' OR LOWER(p.Title) LIKE '%python%' ESCAPE '\') AS HasSpecificTechKeyword,
        -- Complex engagement metric combining score, view count, comments, answers, and favorites, handling potential division by zero.
        ROUND(
            (CAST(p.Score AS NUMERIC) / NULLIF(p.ViewCount, 0))
            * (p.CommentCount + p.AnswerCount + COALESCE(p.FavoriteCount, 0) + 1), -- Add 1 to avoid zero multiplication effect
            2
        ) AS CalculatedEngagementMetric,
        -- Check if the post's body contains the string 'NULL' or 'null'
        (p.Body LIKE '%NULL%' OR p.Body LIKE '%null%') AS BodyMentionsNULL
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON ph_close.PostHistoryTypeId = 10 AND crt.Id = CAST(ph_close.Comment AS SMALLINT)
    LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Body
),
UserBadgeTagInsights AS (
    -- CTE 3: Gathers badge-related insights for users, distinguishing by class and type.
    -- Includes correlated subqueries to find the latest badge and most frequent badge class.
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgesCount,
        COUNT(b.Id) FILTER (WHERE b.TagBased = TRUE) AS TagBasedBadgesCount,
        COUNT(b.Id) FILTER (WHERE b.TagBased = FALSE) AS NamedBadgesCount,
        -- Correlated subquery: Retrieve the name of the most recently awarded badge for the user.
        (SELECT b2.Name FROM Badges b2 WHERE b2.UserId = u.Id ORDER BY b2.Date DESC LIMIT 1) AS LatestBadgeName,
        -- Correlated subquery: Determine the badge class (Gold, Silver, Bronze) the user has most frequently received.
        (SELECT b3.Class
         FROM Badges b3
         WHERE b3.UserId = u.Id
         GROUP BY b3.Class
         ORDER BY COUNT(b3.Class) DESC, b3.Class ASC
         LIMIT 1) AS MostFrequentBadgeClass
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
)
-- Main query: Joins the CTEs and applies complex filtering, window functions, and advanced expressions
-- to retrieve a comprehensive view of highly engaged users and their influential posts.
SELECT
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.TotalQuestionsPosted,
    uam.TotalAnswersPosted,
    uam.TotalPostsCreated,
    uam.AverageScorePerPost,
    uam.DistinctQuestionTagsCount,
    ubi.GoldBadgesCount,
    ubi.SilverBadgesCount,
    ubi.BronzeBadgesCount,
    ubi.LatestBadgeName,
    ubi.MostFrequentBadgeClass,
    pda.PostId,
    pda.PostTypeId,
    pda.PostCreationDate,
    pda.PostScore,
    pda.PostScoreRankWithinType,
    pda.Title AS PostTitle,
    pda.Tags AS PostTags,
    pda.EditCount,
    pda.LatestCloseReason,
    pda.LinkedPostCount,
    pda.DuplicatePostCount,
    pda.AverageAnswerScore,
    pda.HasSpecificTechKeyword,
    pda.CalculatedEngagementMetric,
    pda.BodyMentionsNULL,
    -- Window function: Get the score of the previous post by the same owner, ordered by creation date.
    LAG(pda.PostScore, 1, 0) OVER (PARTITION BY uam.UserId ORDER BY pda.PostCreationDate) AS PreviousPostScore,
    -- Window function: Get the score of the next post by the same owner, ordered by creation date.
    LEAD(pda.PostScore, 1, 0) OVER (PARTITION BY uam.UserId ORDER BY pda.PostCreationDate) AS NextPostScore,
    -- Window function: Calculate a 3-post rolling average of post scores for each user.
    AVG(pda.PostScore) OVER (PARTITION BY uam.UserId ORDER BY pda.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserRollingAvgPostScore,
    -- Complex CASE expression for categorizing posts based on multiple criteria.
    CASE
        WHEN pda.CalculatedEngagementMetric IS NULL THEN 'Engagement Data Missing'
        WHEN pda.CalculatedEngagementMetric > 1000 AND pda.PostScoreRankWithinType = 1 THEN 'Highly Engaged Top-Ranked Post'
        WHEN pda.HasSpecificTechKeyword AND pda.EditCount > 3 AND pda.LatestCloseReason IS NULL THEN 'Tech-Specific, Frequently Edited, Open'
        WHEN pda.AverageAnswerScore IS NOT NULL AND pda.AverageAnswerScore > 7 AND pda.PostTypeId = 1 THEN 'Question with Highly-Rated Answers'
        WHEN pda.BodyMentionsNULL AND pda.PostScore < 0 THEN 'Null Discussion with Negative Score'
        ELSE 'General Post Category'
    END AS PostCategoryDescription,
    -- Elaborate string expression: Truncate title, append ellipsis if needed, and combine with owner's display name or 'Community User'.
    TRIM(SUBSTRING(pda.Title, 1, 75)) || CASE WHEN LENGTH(pda.Title) > 75 THEN '...' ELSE '' END
    || ' [by: ' || COALESCE(uam.DisplayName, 'Community User') || ' | Rep: ' || uam.Reputation || ']' AS PostDetailSummary
FROM UserActivityMetrics uam
INNER JOIN PostDetailAnalysis pda ON uam.UserId = pda.OwnerUserId
LEFT JOIN UserBadgeTagInsights ubi ON uam.UserId = ubi.UserId
WHERE
    uam.Reputation > 5000 -- Filter for users with significant reputation
    AND uam.TotalPostsCreated > 10 -- Ensure users are active
    AND uam.AccountAgeDays > 365 * 2 -- Filter for accounts older than 2 years
    AND (
        (pda.PostTypeId = 1 AND pda.PostScore > 10 AND pda.AnswerCount > 2) -- High-score questions with multiple answers
        OR
        (pda.PostTypeId = 2 AND pda.PostScore > 20 AND pda.AverageAnswerScore IS NOT NULL AND pda.AverageAnswerScore > 5) -- Very high-score answers
    )
    AND NOT (pda.LatestCloseReason IS NOT NULL AND pda.EditCount < 2) -- Exclude poorly handled closed posts (closed quickly without much editing)
    AND EXISTS ( -- Correlated EXISTS subquery: only include users who have at least one question with more than 5 comments
        SELECT 1
        FROM Posts excl_p
        WHERE excl_p.OwnerUserId = uam.UserId
          AND excl_p.PostTypeId = 1
          AND excl_p.CommentCount > 5
    )
ORDER BY
    uam.Reputation DESC,
    pda.CalculatedEngagementMetric DESC NULLS LAST,
    uam.LastUserAccessDate DESC
LIMIT 1000;