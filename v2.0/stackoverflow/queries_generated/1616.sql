-- {"query": "1616.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2877} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.ViewCount) AS AvgPostViewCount,
        -- Calculate an 'Engagement Score' based on various user metrics
        (U.Reputation * 0.5) + (U.UpVotes * 0.2) - (U.DownVotes * 0.1) + (COUNT(DISTINCT P.Id) * 5) + (COUNT(DISTINCT C.Id) * 1) AS EngagementScore,
        -- Categorize users into reputation tiers
        NTILE(5) OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS ReputationTier,
        -- Calculate the proportion of upvotes to total votes, handling division by zero
        CAST(U.UpVotes AS NUMERIC) / NULLIF((U.UpVotes + U.DownVotes), 0) AS UpvoteRatio
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes,
        U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0 -- Only users with some activity
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.Title,
        P.Body,
        P.Tags,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        -- Calculate a 'PostPopularityScore'
        (COALESCE(P.AnswerCount, 0) * 10) + (P.Score * 5) + (COALESCE(P.FavoriteCount, 0) * 2) + (COALESCE(P.ViewCount, 0) / 100) AS PostPopularityScore,
        -- Extract the primary tag from the tags string
        NULLIF(SUBSTRING(P.Tags FROM 2 FOR POSITION('><' IN P.Tags) - 2), '') AS PrimaryTag,
        -- Check for common problematic words in title using case-insensitive match
        (CASE WHEN LOWER(P.Title) LIKE '%problem%' OR LOWER(P.Title) LIKE '%error%' OR LOWER(P.Title) LIKE '%bug%' OR LOWER(P.Title) LIKE '%help%' THEN TRUE ELSE FALSE END) AS IsProblematicTitle,
        -- Count of distinct editors from PostHistory
        COUNT(DISTINCT PH.UserId) AS DistinctEditorCount,
        MAX(PH.CreationDate) AS LastEditHistoryDate
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9) -- Only consider actual edit history types
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions or Answers
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.Title, P.Body, P.Tags
),
PostActivityTimelines AS (
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) AS FirstHistoryEntry,
        MAX(PH.CreationDate) AS LastHistoryEntry,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        -- Calculate the time difference between first and last history entries for a post
        AGE(MAX(PH.CreationDate), MIN(PH.CreationDate)) AS PostLifespanInHistory
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
QuestionAnswerChains AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.AcceptedAnswerId,
        -- Correlated subquery: Count badges for the question owner before the question was created
        (SELECT COUNT(DISTINCT B_corr.Id) FROM Badges AS B_corr WHERE B_corr.UserId = Q.OwnerUserId AND B_corr.Date < Q.CreationDate) AS QuestionOwnerBadgesBeforePost,
        -- Correlated subquery: Count badges for the answer owner before the answer was created
        (SELECT COUNT(DISTINCT B_corr.Id) FROM Badges AS B_corr WHERE B_corr.UserId = A.OwnerUserId AND B_corr.Date < A.CreationDate) AS AnswerOwnerBadgesBeforePost,
        -- Rank answers for each question by score, then creation date
        ROW_NUMBER() OVER (PARTITION BY Q.Id ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRankByScore,
        -- Calculate the time difference between question and answer
        AGE(A.CreationDate, Q.CreationDate) AS TimeToAnswer
    FROM Posts AS Q
    INNER JOIN Posts AS A ON Q.Id = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
),
DuplicateLinkAnalysis AS (
    SELECT
        PL.PostId,
        COUNT(PL.RelatedPostId) AS DuplicateCount,
        STRING_AGG(CAST(PL.RelatedPostId AS VARCHAR), ', ' ORDER BY PL.RelatedPostId) AS RelatedDuplicatePostIds,
        MAX(PL.CreationDate) AS LastDuplicateLinkDate
    FROM PostLinks AS PL
    WHERE PL.LinkTypeId = 3 -- LinkType 3 is 'Duplicate'
    GROUP BY PL.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.EngagementScore,
    UAS.ReputationTier,
    UAS.UpvoteRatio,
    PCA.PostId,
    PCA.PostTypeId,
    PCA.Title,
    PCA.PostScore,
    PCA.PostViewCount,
    PCA.AnswerCount,
    PCA.PostCommentCount,
    PCA.PrimaryTag,
    PCA.IsProblematicTitle,
    PCA.BodyLength,
    PCA.DistinctEditorCount,
    PT.EditCount AS PostHistoryEditCount,
    PT.CloseCount,
    PT.ReopenCount,
    PT.LastClosedDate,
    PT.LastReopenedDate,
    QA.QuestionId,
    QA.QuestionTitle,
    QA.AnswerId,
    QA.AnswerScore,
    QA.AnswerRankByScore,
    QA.QuestionOwnerBadgesBeforePost,
    QA.AnswerOwnerBadgesBeforePost,
    QA.TimeToAnswer,
    DLA.DuplicateCount,
    DLA.RelatedDuplicatePostIds,
    -- Determine a complex 'PostStatusCategory' based on various conditions
    CASE
        WHEN PT.CloseCount > 0 AND PT.ReopenCount > 0 THEN 'ClosedAndReopened'
        WHEN PT.CloseCount > 0 AND PT.ReopenCount = 0 THEN 'ClosedOnly'
        WHEN PCA.PostScore < 0 AND PCA.PostViewCount > 5000 THEN 'NegativeScoreHighViews'
        WHEN PCA.PostPopularityScore > 750 THEN 'HighlyPopular'
        WHEN PCA.IsProblematicTitle = TRUE AND PCA.EditCount > 3 THEN 'ProblematicAndEdited'
        WHEN QA.AcceptedAnswerId IS NOT NULL AND QA.TimeToAnswer < INTERVAL '1 hour' THEN 'QuicklyAnsweredAndAccepted'
        ELSE 'NormalEngagement'
    END AS PostStatusCategory,
    -- Calculate time since last activity for posts, handling potential NULLs
    AGE(NOW(), COALESCE(PT.LastHistoryEntry, PCA.LastEditHistoryDate, PCA.PostCreationDate)) AS TimeSinceLastPostActivity,
    -- Calculate the average score of comments for a given post using a correlated subquery
    (SELECT AVG(C_sub.Score) FROM Comments AS C_sub WHERE C_sub.PostId = PCA.PostId) AS AvgCommentScoreForPost,
    -- Rolling average reputation for users within their reputation tier (for posts they own)
    AVG(UAS.Reputation) OVER (PARTITION BY UAS.ReputationTier ORDER BY UAS.Reputation DESC) AS AvgReputationInTier,
    -- Rank posts by popularity score within their primary tag group
    RANK() OVER (PARTITION BY PCA.PrimaryTag ORDER BY PCA.PostPopularityScore DESC, PCA.PostCreationDate DESC) AS PostPopularityRankInTag
FROM UserActivitySummary AS UAS
INNER JOIN PostContentAnalysis AS PCA ON UAS.UserId = PCA.OwnerUserId
LEFT JOIN PostActivityTimelines AS PT ON PCA.PostId = PT.PostId
LEFT JOIN QuestionAnswerChains AS QA ON PCA.PostId = QA.QuestionId
LEFT JOIN DuplicateLinkAnalysis AS DLA ON PCA.PostId = DLA.PostId
WHERE
    UAS.ReputationTier <= 3 -- Focus on users in the top 3 reputation tiers
    AND PCA.PostPopularityScore >= 150 -- Only posts with significant engagement
    AND PCA.PostTypeId = 1 -- Limit the main output to questions
    AND (
        PCA.Tags ILIKE '%<sql>%' OR PCA.Tags ILIKE '%<database>%' OR PCA.Tags ILIKE '%<performance>%'
        OR PCA.PrimaryTag IN ('python', 'java', 'c#') -- Include common language tags for variety
        OR PCA.IsProblematicTitle = TRUE -- Include posts flagged as problematic
    )
    AND (QA.AnswerRankByScore = 1 OR QA.AnswerRankByScore IS NULL) -- Only consider the top answer or questions without answers
    AND (DLA.DuplicateCount IS NULL OR DLA.DuplicateCount < 3) -- Exclude questions that are duplicates of many others
    AND UAS.LastAccessDate >= (NOW() - INTERVAL '1 year 6 months') -- Users active within the last 1.5 years
    AND PCA.CreationDate BETWEEN (NOW() - INTERVAL '6 years') AND (NOW() - INTERVAL '2 years') -- Posts created between 2 and 6 years ago
    AND (PT.EditCount IS NULL OR PT.EditCount < 10) -- Exclude extremely heavily edited posts to avoid noise
    AND COALESCE(PCA.BodyLength, 0) > 100 -- Ensure posts have a substantial body
ORDER BY
    UAS.EngagementScore DESC,
    PCA.PostPopularityScore DESC,
    PCA.PostId
LIMIT 7500;
