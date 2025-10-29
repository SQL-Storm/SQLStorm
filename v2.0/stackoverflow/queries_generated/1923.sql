-- {"query": "1923.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3987} 

WITH UserBaseStats AS (
    -- CTE 1: Summarizes core user statistics, activity, and calculated metrics.
    -- It uses LEFT JOINs to ensure all users are considered, even if they have no posts, comments, or votes directly attributed.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalQuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS UpvotesCast,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS DownvotesCast,
        -- Uses GREATEST and COALESCE to find the absolute latest interaction date, handling potential NULLs.
        MAX(GREATEST(COALESCE(U.LastAccessDate, U.CreationDate), COALESCE(P.LastActivityDate, '1900-01-01'), COALESCE(C.CreationDate, '1900-01-01'))) AS LastInteractionDate,
        -- Calculates user age in days using EXTRACT for performance-critical date math.
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (3600 * 24) AS DaysSinceCreation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING U.Reputation > 100 -- Filters for more established users to reduce dataset size.
),
PostTagExplosion AS (
    -- CTE 2: Explodes the 'Tags' string column into individual tag rows per post.
    -- This uses string_to_array and UNNEST for robust tag parsing as per schema hint.
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.PostTypeId IN (1, 2)
),
PostDetailedAnalysis AS (
    -- CTE 3: Provides in-depth analysis for individual posts, incorporating various subqueries and string functions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.Title,
        P.Tags,
        P.ClosedDate,
        P.AcceptedAnswerId,
        -- Correlated subquery: Calculates the average score of all answers related to this question.
        (SELECT AVG(SA.Score) FROM Posts AS SA WHERE SA.ParentId = P.Id AND SA.PostTypeId = 2) AS AvgRelatedAnswerScore,
        -- Correlated subquery: Counts distinct users who have edited this post.
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6, 8)) AS DistinctEditorCount,
        -- Correlated subquery with EXISTS: Checks if the post is a source of a duplicate link.
        EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 AND PL.RelatedPostId <> P.Id) AS IsDuplicateSource,
        -- Complex CASE statement using EXISTS with PostTagExplosion to categorize posts by technology stacks.
        CASE
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('javascript', 'reactjs')) AND
                 EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName = 'reactjs') THEN 'JS_React_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('java', 'spring')) THEN 'Java_Spring_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('python', 'django')) THEN 'Python_Django_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('c#', '.net')) THEN 'CSharp_DotNet_Framework'
            WHEN P.Tags IS NULL OR P.Tags = '' THEN 'No_Tags'
            ELSE 'Other_Framework_Or_Tech'
        END AS TagFrameworkCategory,
        NULLIF(P.CommentCount, 0) AS ActualCommentCount, -- Uses NULLIF to treat zero comment count as NULL.
        -- Calculates occurrences of 'code' keyword in the body using string manipulation.
        (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, 'code', ''))) / GREATEST(LENGTH('code'), 1) AS CodeKeywordCount, -- Division by 0 guard.
        -- NULL logic: Checks if an AcceptedAnswerId exists AND if it belongs to a different user.
        CASE WHEN P.AcceptedAnswerId IS NOT NULL AND (SELECT OwnerUserId FROM Posts WHERE Id = P.AcceptedAnswerId) <> P.OwnerUserId THEN TRUE ELSE FALSE END AS AcceptedByOtherUser
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2) -- Filters for Questions (1) and Answers (2).
      AND P.CreationDate BETWEEN '2023-01-01' AND '2023-12-31' -- Filters for a specific time range.
      AND P.Body IS NOT NULL AND LENGTH(P.Body) > 100 -- Ensures substantial content.
),
CommentSentiment AS (
    -- CTE 4: Analyzes comments related to posts, calculating total comments, max score, and simple sentiment flags.
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        MAX(C.Score) AS MaxCommentScore,
        AVG(C.Score) AS AvgCommentScore,
        SUM(CASE WHEN C.Text LIKE '%thank%' OR C.Text LIKE '%helpful%' OR C.Text LIKE '%solved%' THEN 1 ELSE 0 END) AS PositiveCommentFlags,
        SUM(CASE WHEN C.Text LIKE '%bug%' OR C.Text LIKE '%error%' OR C.Text LIKE '%wrong%' OR C.Text LIKE '%clarify%' THEN 1 ELSE 0 END) AS ConstructiveCommentFlags
    FROM Comments AS C
    WHERE C.CreationDate >= '2023-01-01' AND C.Text IS NOT NULL
    GROUP BY C.PostId
),
PostAggregatedMetrics AS (
    -- CTE 5: Combines post details with comment sentiment and applies various window functions for ranking and aggregation.
    SELECT
        PDA.*,
        COALESCE(CS.TotalCommentsOnPost, 0) AS RelatedCommentsCount,
        CS.MaxCommentScore,
        CS.AvgCommentScore,
        CS.PositiveCommentFlags,
        CS.ConstructiveCommentFlags,
        -- Window function: Ranks posts by score within each user's contributions.
        ROW_NUMBER() OVER (PARTITION BY PDA.OwnerUserId ORDER BY PDA.PostScore DESC, PDA.CreationDate DESC) AS PostRankByUser,
        -- Window function: Ranks posts by view count within each TagFrameworkCategory.
        RANK() OVER (PARTITION BY PDA.TagFrameworkCategory ORDER BY PDA.ViewCount DESC, PDA.PostScore DESC) AS ViewRankByTagCategory,
        -- Window function: Calculates the average post score for each TagFrameworkCategory.
        AVG(PDA.PostScore) OVER (PARTITION BY PDA.TagFrameworkCategory) AS AvgTagCategoryScore,
        -- Window function: Counts total posts by each user within the filtered period.
        COUNT(PDA.PostId) OVER (PARTITION BY PDA.OwnerUserId) AS UserTotalPostsInPeriod,
        -- Window function: Calculates a running average of post scores for a user's posts, ordered by creation date.
        AVG(PDA.PostScore) OVER (PARTITION BY PDA.OwnerUserId ORDER BY PDA.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgUserPostScore
    FROM PostDetailedAnalysis AS PDA
    LEFT JOIN CommentSentiment AS CS ON PDA.PostId = CS.PostId
),
UserPostCombined AS (
    -- CTE 6: Joins user base statistics with aggregated post metrics and calculates a complex weighted score.
    SELECT
        UBS.UserId,
        UBS.DisplayName,
        UBS.Reputation,
        UBS.TotalQuestionsAsked,
        UBS.TotalAnswersPosted,
        UBS.TotalCommentsMade,
        UBS.UpvotesCast,
        UBS.DownvotesCast,
        UBS.LastInteractionDate,
        UBS.DaysSinceCreation,
        PAM.PostId,
        PAM.PostTypeId,
        PAM.PostCreationDate,
        PAM.PostScore,
        PAM.ViewCount,
        PAM.AnswerCount,
        PAM.FavoriteCount,
        PAM.Title,
        PAM.Tags,
        PAM.ClosedDate,
        PAM.AcceptedAnswerId,
        PAM.AvgRelatedAnswerScore,
        PAM.DistinctEditorCount,
        PAM.IsDuplicateSource,
        PAM.TagFrameworkCategory,
        PAM.ActualCommentCount,
        PAM.CodeKeywordCount,
        PAM.AcceptedByOtherUser,
        PAM.RelatedCommentsCount,
        PAM.MaxCommentScore,
        PAM.AvgCommentScore,
        PAM.PositiveCommentFlags,
        PAM.ConstructiveCommentFlags,
        PAM.PostRankByUser,
        PAM.ViewRankByTagCategory,
        PAM.AvgTagCategoryScore,
        PAM.UserTotalPostsInPeriod,
        PAM.RunningAvgUserPostScore,
        EXTRACT(EPOCH FROM (NOW() - PAM.PostCreationDate)) / (3600 * 24) AS PostAgeInDays,
        -- Complex weighted score calculation incorporating multiple post quality metrics and NULL handling.
        (PAM.PostScore * 0.4 +
         COALESCE(PAM.AvgRelatedAnswerScore, 0) * 0.2 +
         PAM.RelatedCommentsCount * 0.1 +
         PAM.FavoriteCount * 0.15 +
         (CASE WHEN PAM.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END) * 0.15 -- Bonus for posts with accepted answers.
        ) AS WeightedPostScore
    FROM UserBaseStats AS UBS
    INNER JOIN PostAggregatedMetrics AS PAM ON UBS.UserId = PAM.OwnerUserId
    WHERE PAM.PostRankByUser <= 5 -- Filters for top 5 posts by score for each user.
      AND PAM.ViewRankByTagCategory <= 10 -- Filters for top 10 posts by view count within their tag category.
      AND PAM.ActualCommentCount IS NOT NULL -- Ensures posts have comments.
      AND PAM.IsDuplicateSource = FALSE -- Excludes posts that are sources of duplicates.
),
HighlyEngagedQuestions AS (
    -- CTE 7: Filters UserPostCombined for highly engaged questions, forming the first branch of the UNION ALL.
    SELECT
        UPC.PostId,
        UPC.Title,
        UPC.OwnerUserId,
        UPC.DisplayName AS OwnerDisplayName,
        UPC.Reputation,
        UPC.PostScore,
        UPC.ViewCount,
        UPC.FavoriteCount,
        UPC.TagFrameworkCategory,
        UPC.WeightedPostScore,
        UPC.PostAgeInDays,
        UPC.RunningAvgUserPostScore,
        UPC.AcceptedByOtherUser,
        UPC.PostCreationDate, -- Included for final correlated subquery
        'ActiveQuestion_Segment' AS EntryType
    FROM UserPostCombined AS UPC
    WHERE UPC.PostTypeId = 1 -- Questions
      AND UPC.PostScore > 50
      AND UPC.ViewCount > 5000
      AND UPC.TotalQuestionsAsked > 0
      AND UPC.PostAgeInDays < 365
      AND UPC.PositiveCommentFlags > COALESCE(UPC.ConstructiveCommentFlags, 0) -- More positive than constructive comments.
      AND UPC.AvgRelatedAnswerScore IS NOT NULL AND UPC.AvgRelatedAnswerScore > 15
      AND UPC.ActualCommentCount > 5
),
ExpertContributorAnswers AS (
    -- CTE 8: Filters UserPostCombined for well-received answers from expert contributors, forming the second branch.
    SELECT
        UPC.PostId,
        UPC.Title,
        UPC.OwnerUserId,
        UPC.DisplayName AS OwnerDisplayName,
        UPC.Reputation,
        UPC.PostScore,
        UPC.ViewCount,
        UPC.FavoriteCount,
        UPC.TagFrameworkCategory,
        UPC.WeightedPostScore,
        UPC.PostAgeInDays,
        UPC.RunningAvgUserPostScore,
        UPC.AcceptedByOtherUser,
        UPC.PostCreationDate, -- Included for final correlated subquery
        'ExpertAnswer_Segment' AS EntryType
    FROM UserPostCombined AS UPC
    WHERE UPC.PostTypeId = 2 -- Answers
      AND UPC.PostScore > 30
      AND UPC.Reputation > 7500 -- From highly reputable users.
      AND UPC.AcceptedAnswerId IS NOT NULL -- Parent question has an accepted answer.
      AND UPC.PostRankByUser = 1 -- This is the user's highest scored answer in the period.
      AND UPC.CodeKeywordCount > 3 -- Indicates a very detailed technical answer.
      AND UPC.PostAgeInDays < 180 -- Relatively recent answers.
)
-- Final SELECT statement: Combines the two complex result sets using UNION ALL.
-- Includes additional correlated subqueries and strict ordering and limiting.
SELECT
    FinalOutput.PostId,
    FinalOutput.Title,
    FinalOutput.OwnerDisplayName,
    FinalOutput.Reputation,
    FinalOutput.PostScore,
    FinalOutput.ViewCount,
    FinalOutput.FavoriteCount,
    FinalOutput.TagFrameworkCategory,
    FinalOutput.WeightedPostScore,
    FinalOutput.PostAgeInDays,
    FinalOutput.RunningAvgUserPostScore,
    FinalOutput.AcceptedByOtherUser,
    FinalOutput.EntryType,
    -- Correlated subquery: Counts distinct users who made positive comments on this post after its creation.
    (SELECT COUNT(DISTINCT C.UserId)
     FROM Comments AS C
     WHERE C.PostId = FinalOutput.PostId
       AND C.CreationDate >= FinalOutput.PostCreationDate
       AND C.Score > 0) AS UniquePositiveCommentersCount,
    -- Correlated subquery: Retrieves the body text of the latest body edit for the post.
    (SELECT PH.Text FROM PostHistory PH WHERE PH.PostId = FinalOutput.PostId AND PH.PostHistoryTypeId = 5 ORDER BY PH.CreationDate DESC LIMIT 1) AS LatestBodyEditSnapshot
FROM (
    SELECT
        HQ.PostId, HQ.Title, HQ.OwnerDisplayName, HQ.Reputation, HQ.PostScore, HQ.ViewCount, HQ.FavoriteCount,
        HQ.TagFrameworkCategory, HQ.WeightedPostScore, HQ.PostAgeInDays, HQ.RunningAvgUserPostScore, HQ.AcceptedByOtherUser,
        HQ.EntryType, HQ.PostCreationDate
    FROM HighlyEngagedQuestions AS HQ
    WHERE HQ.WeightedPostScore > 80 -- Final filter for highly engaged questions.

    UNION ALL

    SELECT
        EA.PostId, EA.Title, EA.OwnerDisplayName, EA.Reputation, EA.PostScore, EA.ViewCount, EA.FavoriteCount,
        EA.TagFrameworkCategory, EA.WeightedPostScore, EA.PostAgeInDays, EA.RunningAvgUserPostScore, EA.AcceptedByOtherUser,
        EA.EntryType, EA.PostCreationDate
    FROM ExpertContributorAnswers AS EA
    WHERE EA.WeightedPostScore > 60 -- Final filter for expert answers.
    AND EA.RunningAvgUserPostScore > 20 -- Ensures the contributor generally produces high-quality posts.
) AS FinalOutput
ORDER BY FinalOutput.WeightedPostScore DESC, FinalOutput.Reputation DESC, FinalOutput.PostAgeInDays ASC
LIMIT 1000; -- Limits the final result set size for practical benchmarking.
