-- {"query": "1303.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3548} 

WITH UserActivitySummary AS (
    -- Summarizes user-level engagement and reputation metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersProvided,
        MAX(P.LastActivityDate) AS LastPostActivity,
        -- Calculate average score of posts owned by the user, handling NULLs
        COALESCE(AVG(P.Score), 0) AS AvgPostScoreOwned,
        -- Calculate the ratio of accepted answers to total answers, NULL if no answers
        NULLIF(CAST(SUM(CASE WHEN P_Answer.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS DECIMAL(10,2)) / NULLIF(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0), 0) AS AcceptedAnswerRatio,
        -- Rank users based on their reputation, total posts, and comments
        NTILE(5) OVER (ORDER BY U.Reputation DESC, COUNT(DISTINCT P.Id) DESC, COUNT(DISTINCT C.Id) DESC) AS OverallEngagementTier
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P_Answer ON P_Answer.AcceptedAnswerId = P.Id AND P.PostTypeId = 2 -- Link answers to questions that accepted them
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostRevisionAnalysis AS (
    -- Identifies posts with significant history changes (edits, closes, reopens)
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreatedDate,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS TotalRevisions, -- Edits and Rollbacks
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS TotalCloseEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS TotalReopenEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.Id END) AS TotalDeletionEvents,
        -- Check if post has ever been closed and then reopened
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        -- Calculate the age of the post at its first close, if applicable
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN AGE(PH.CreationDate, P.CreationDate) END) AS AgeAtFirstClose
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate
),
AggregatedPostMetrics AS (
    -- Combines general post statistics with revision analysis
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS CurrentScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.CreationDate,
        P.LastActivityDate,
        P.AcceptedAnswerId,
        PRA.TotalRevisions,
        PRA.TotalCloseEvents,
        PRA.TotalReopenEvents,
        PRA.TotalDeletionEvents,
        PRA.WasClosed,
        PRA.WasReopened,
        PRA.AgeAtFirstClose,
        -- Average score of comments on this post, defaulting to 0 for posts with no comments
        COALESCE(AVG(C.Score), 0) AS AvgCommentScoreForPost,
        -- Calculate time since last activity in days, handling NULL LastActivityDate
        EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / 86400 AS DaysSinceLastActivity,
        -- Identify "Highly Volatile" posts based on revision and close/reopen events
        CASE
            WHEN PRA.TotalRevisions > 5 AND (PRA.TotalCloseEvents > 0 OR PRA.TotalReopenEvents > 0) THEN 'Highly Volatile'
            WHEN PRA.TotalRevisions > 2 AND P.CommentCount > 10 THEN 'Moderately Volatile'
            ELSE 'Stable'
        END AS VolatilityCategory
    FROM Posts P
    LEFT JOIN PostRevisionAnalysis PRA ON P.Id = PRA.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community-owned posts or deleted users
      AND P.CreationDate >= '2015-01-01' -- Focus on more recent data
    GROUP BY P.Id, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.Title, P.Tags, P.CreationDate, P.LastActivityDate, P.AcceptedAnswerId, PRA.TotalRevisions, PRA.TotalCloseEvents, PRA.TotalReopenEvents, PRA.WasClosed, PRA.WasReopened, PRA.AgeAtFirstClose, PRA.TotalDeletionEvents
),
TagInfluence AS (
    -- Ranks tags by influence (popularity + score)
    SELECT
        TagName,
        QuestionCount,
        AverageQuestionScore,
        SUM(TotalAnswersForTag) AS TotalAnswersForTag,
        -- Divide tags into 4 quartiles based on influence
        NTILE(4) OVER (ORDER BY QuestionCount DESC, AverageQuestionScore DESC) AS TagInfluenceQuartile
    FROM (
        SELECT
            TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
            COUNT(DISTINCT P.Id) AS QuestionCount,
            AVG(P.Score) AS AverageQuestionScore,
            SUM(P.AnswerCount) AS TotalAnswersForTag -- Sum of answers for questions with this tag
        FROM Posts P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
        GROUP BY TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))
    ) AS TagAggregates
    WHERE QuestionCount > 50 AND AverageQuestionScore > 2 -- Filter out insignificant tags
    GROUP BY TagName, QuestionCount, AverageQuestionScore
)
-- Main Query: Find influential users engaging with popular/volatile content
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsOwned,
    UAS.TotalCommentsMade,
    UAS.TotalBadgesEarned,
    APM.PostId,
    APM.Title AS PostTitle,
    APM.CurrentScore AS PostScore,
    APM.ViewCount AS PostViewCount,
    APM.AnswerCount AS PostAnswerCount,
    APM.VolatilityCategory,
    TI.TagName AS PrimaryTag,
    TI.TagInfluenceQuartile,
    -- Correlated subquery: Count how many *other* questions by this user have high scores
    (SELECT COUNT(DISTINCT P2.Id)
     FROM Posts P2
     WHERE P2.OwnerUserId = UAS.UserId
       AND P2.PostTypeId = 1
       AND P2.Id != APM.PostId
       AND P2.Score > (SELECT AVG(P3.Score) FROM Posts P3 WHERE P3.OwnerUserId = UAS.UserId AND P3.PostTypeId = 1)) AS OtherHighScoringQuestionsByOwner,
    -- Window function: Rank posts by score within each user's questions
    RANK() OVER (PARTITION BY UAS.UserId ORDER BY APM.CurrentScore DESC, APM.ViewCount DESC) AS RankOfPostForUser,
    -- Complicated calculation/expression involving NULL logic and string operations to categorize content engagement
    COALESCE(
        CASE
            WHEN APM.VolatilityCategory = 'Highly Volatile' AND APM.TotalCloseEvents > 0 THEN 'Closed & Volatile Question'
            WHEN APM.WasReopened = 1 AND APM.TotalRevisions > 3 THEN 'Reopened Highly Edited Question'
            WHEN APM.FavoriteCount > 100 AND APM.AnswerCount > 5 THEN 'Highly Engaged Question'
            ELSE 'Standard Question'
        END,
        'Unknown Question Type'
    ) AS ContentEngagementType,
    -- String expression to extract the first tag, handling possible NULLs or empty strings for Tags column
    SUBSTRING(APM.Tags FROM POSITION('<' IN APM.Tags) + 1 FOR POSITION('>' IN APM.Tags) - POSITION('<' IN APM.Tags) - 1) AS FirstTag,
    -- Window function: Calculate average days from creation to last activity for all posts by this user, excluding very recent ones
    AVG(APM.DaysSinceLastActivity) OVER (PARTITION BY UAS.UserId) AS AvgDaysToLastActivityForUserPosts,
    -- Check if the user has any 'Gold' badges related to a highly influential tag for this specific post
    EXISTS (SELECT 1 FROM Badges B JOIN TagInfluence TI2 ON B.Name ILIKE '%' || TI2.TagName || '%' WHERE B.UserId = UAS.UserId AND B.Class = 1 AND TI2.TagInfluenceQuartile = 1 AND B.Date <= APM.CreationDate) AS HasRelevantGoldBadge
FROM UserActivitySummary UAS
INNER JOIN AggregatedPostMetrics APM ON UAS.UserId = APM.OwnerUserId
LEFT JOIN TagInfluence TI ON APM.Tags LIKE '<' || TI.TagName || '>' || '%' -- Matches the first tag of the post to TagInfluence
WHERE UAS.Reputation > 10000 -- Focus on highly reputable users
  AND UAS.TotalPostsOwned > 10 -- Active contributors
  AND APM.PostTypeId = 1 -- Only questions for this primary analysis segment
  AND APM.CurrentScore > 10
  AND APM.ViewCount > 1000
  AND APM.TotalRevisions > 1 -- Ensure posts have been edited at least once
  AND (APM.VolatilityCategory = 'Highly Volatile' OR APM.VolatilityCategory = 'Moderately Volatile')
  AND (TI.TagInfluenceQuartile IS NULL OR TI.TagInfluenceQuartile <= 2) -- Either a primary tag that is influential or no primary tag (can happen if tag isn't in TagInfluence CTE)
  AND APM.CreationDate BETWEEN '2022-01-01' AND '2023-01-01' -- Specific timeframe
  AND APM.DaysSinceLastActivity < 365 -- Only consider posts active within the last year
-- First part: Influential users on volatile questions
UNION ALL
-- Second part: Influential users providing high-impact answers on well-regarded topics
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsOwned,
    UAS.TotalCommentsMade,
    UAS.TotalBadgesEarned,
    APM.PostId,
    APM.Title AS PostTitle,
    APM.CurrentScore AS PostScore,
    APM.ViewCount AS PostViewCount,
    APM.AnswerCount AS PostAnswerCount,
    APM.VolatilityCategory,
    TI.TagName AS PrimaryTag,
    TI.TagInfluenceQuartile,
    -- Correlated subquery: Count how many *other* answers by this user have high scores
    (SELECT COUNT(DISTINCT P2.Id)
     FROM Posts P2
     WHERE P2.OwnerUserId = UAS.UserId
       AND P2.PostTypeId = 2 -- Other answers
       AND P2.Id != APM.PostId
       AND P2.Score > (SELECT AVG(P3.Score) FROM Posts P3 WHERE P3.OwnerUserId = UAS.UserId AND P3.PostTypeId = 2)) AS OtherHighScoringAnswersByOwner,
    RANK() OVER (PARTITION BY UAS.UserId ORDER BY APM.CurrentScore DESC, APM.CreationDate DESC) AS RankOfPostForUser,
    COALESCE(
        CASE
            WHEN APM.PostTypeId = 2 AND APM.CurrentScore > 50 AND APM.AcceptedAnswerId IS NOT NULL THEN 'Accepted High-Impact Answer'
            WHEN APM.PostTypeId = 2 AND APM.CurrentScore > 25 THEN 'High-Impact Answer'
            ELSE 'General Answer'
        END,
        'Unknown Answer Type'
    ) AS ContentEngagementType,
    SUBSTRING(APM.Tags FROM POSITION('<' IN APM.Tags) + 1 FOR POSITION('>' IN APM.Tags) - POSITION('<' IN APM.Tags) - 1) AS FirstTag,
    AVG(APM.DaysSinceLastActivity) OVER (PARTITION BY UAS.UserId) AS AvgDaysToLastActivityForUserPosts,
    EXISTS (SELECT 1 FROM Badges B JOIN VoteTypes VT ON B.Name LIKE '%' || VT.Name || '%' WHERE B.UserId = UAS.UserId AND B.Class = 2 AND B.Date >= APM.CreationDate) AS HasRelevantSilverBadge
FROM UserActivitySummary UAS
INNER JOIN AggregatedPostMetrics APM ON UAS.UserId = APM.OwnerUserId
LEFT JOIN TagInfluence TI ON APM.Tags LIKE '<' || TI.TagName || '>' || '%'
WHERE UAS.Reputation > 20000 -- Even higher reputation for the second segment
  AND UAS.AcceptedAnswerRatio IS NOT NULL AND UAS.AcceptedAnswerRatio > 0.5 -- Users with high acceptance rate for their answers
  AND APM.PostTypeId = 2 -- Only answers for this segment
  AND APM.CurrentScore > 25
  AND APM.CreationDate >= '2021-01-01'
  AND APM.WasClosed = 0 -- Exclude closed answers
  AND TI.TagName IS NOT NULL AND TI.TagInfluenceQuartile = 1 -- Only answers in top influential tags
  AND APM.AvgCommentScoreForPost > 5 -- Only answers with highly rated comments
ORDER BY Reputation DESC, PostScore DESC, TotalRevisions DESC
LIMIT 1000;
