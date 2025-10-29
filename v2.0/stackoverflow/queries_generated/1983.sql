-- {"query": "1983.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2981} 

WITH UserActivitySummary AS (
    -- Summarizes user's overall activity, reputation tier, and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN U.Reputation > 150000 THEN 'Diamond Tier'
            WHEN U.Reputation > 75000 THEN 'Platinum Tier'
            WHEN U.Reputation > 30000 THEN 'Gold Tier'
            WHEN U.Reputation > 15000 THEN 'Silver Tier'
            ELSE 'Bronze Tier'
        END AS ReputationTier,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT MAX(PH_inner.CreationDate) FROM PostHistory AS PH_inner WHERE PH_inner.UserId = U.Id) AS LastHistoryActivity,
        -- Correlated subquery for average comment score by this user for comments with a positive score
        (SELECT AVG(C_inner.Score) FROM Comments AS C_inner WHERE C_inner.UserId = U.Id AND C_inner.Score > 0) AS AvgUserPositiveCommentScore
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    -- Only consider users who own at least one question or answer post within a recent timeframe
    WHERE U.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL AND PostTypeId IN (1,2) AND CreationDate >= NOW() - INTERVAL '5 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location
    HAVING U.Reputation > 10000 AND COUNT(DISTINCT B.Id) > 10
),
PostQualityMetrics AS (
    -- Calculates various quality metrics for questions and answers
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        -- Derived engagement score, weighted by various factors
        (COALESCE(P.Score, 0) * 0.45 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.FavoriteCount, 0) * 0.35 + COALESCE(P.AnswerCount, 0) * 0.1) AS DerivedEngagementScore,
        -- Heuristic for counting code blocks based on <code> tag occurrences
        LENGTH(P.Body) - LENGTH(REPLACE(P.Body, '<code>', '')) / LENGTH('<code>') AS CodeBlockHeuristic,
        -- Correlated subquery for distinct users who edited this post
        (SELECT COUNT(DISTINCT PH_edit.UserId) FROM PostHistory AS PH_edit WHERE PH_edit.PostId = P.Id AND PH_edit.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditorsCount,
        -- Ranks posts by score within each user and post type partition
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByUserAndType,
        -- Date of the previous post by the same owner
        LAG(P.CreationDate, 1) OVER(PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostDate,
        -- Cleans and aggregates tags into a comma-separated string
        (SELECT STRING_AGG(LOWER(REPLACE(REPLACE(REPLACE(tag_val, '-', '_'), '.', ''), ',', '')), ', ' ORDER BY tag_val)
         FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS tag_val
         WHERE LENGTH(tag_val) > 0
        ) AS CleanedTagsString,
        -- Correlated subquery for counting duplicate links
        (SELECT COUNT(1) FROM PostLinks PL_inner WHERE PL_inner.PostId = P.Id AND PL_inner.LinkTypeId = 3) AS DuplicateLinkCount
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Filter for a specific time range
      AND P.Score > 10 -- Only posts with a significant score
      AND P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
      AND LENGTH(COALESCE(P.Body, '')) > 100 -- Minimum body length
),
PostHistoryDetails AS (
    -- Gathers specific post history information, especially close reasons and their numeric IDs
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PH.Comment,
        PH.UserId AS HistoryUserId,
        CR.Name AS CloseReasonName,
        -- Extracts the numeric CloseReasonId from the comment if available
        CAST(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE 'CloseReasonId:%' THEN SUBSTRING(PH.Comment, LENGTH('CloseReasonId:') + 1) ELSE NULL END AS SMALLINT) AS CloseReasonId,
        -- Ranks history entries by date for each post to get the latest one
        ROW_NUMBER() OVER(PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CR ON PH.PostHistoryTypeId = 10 AND PH.Comment LIKE 'CloseReasonId:%' AND CAST(SUBSTRING(PH.Comment, LENGTH('CloseReasonId:') + 1) AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 35, 36) -- Post Closed, Reopened, Deleted, Undeleted, Migrated Away/Here
)
-- Main query using UNION ALL to combine two distinct analytical branches
(
    -- Branch 1: High-engagement questions from influential users, with detailed close reason analysis
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.ReputationTier,
        UAS.UserCreationDate,
        UAS.UserLocation,
        PQM.PostId,
        'Question' AS PostCategory,
        PQM.Title AS PostTitle,
        PQM.PostScore,
        PQM.ViewCount,
        PQM.DerivedEngagementScore,
        PQM.CodeBlockHeuristic,
        PQM.CleanedTagsString,
        PHD.CloseReasonName AS LatestCloseReason,
        -- Correlated subquery to sum bounty amounts for this question
        (
            SELECT COALESCE(SUM(V_inner.BountyAmount), 0)
            FROM Votes V_inner
            WHERE V_inner.PostId = PQM.PostId AND V_inner.VoteTypeId = 8 -- BountyStart vote
        ) AS TotalBountyAmount,
        -- Ratio of score to view count, handling division by zero with NULLIF
        NULLIF(PQM.PostScore, 0)::NUMERIC / NULLIF(PQM.ViewCount, 0) AS ScorePerViewRatio,
        -- Rank questions by engagement within their reputation tier
        RANK() OVER (PARTITION BY UAS.ReputationTier ORDER BY PQM.DerivedEngagementScore DESC, PQM.PostCreationDate DESC) AS RankWithinTier,
        'High Engagement Question Analysis' AS AnalysisType,
        PHD.CloseReasonId AS LatestCloseReasonId,
        -- Calculate the time difference between consecutive posts by the same user
        EXTRACT(HOUR FROM (PQM.PostCreationDate - PQM.PreviousPostDate)) AS HoursSincePreviousPost
    FROM UserActivitySummary AS UAS
    INNER JOIN PostQualityMetrics AS PQM ON UAS.UserId = PQM.OwnerUserId
    LEFT JOIN PostHistoryDetails AS PHD ON PQM.PostId = PHD.PostId AND PHD.rn = 1
    WHERE
        PQM.PostTypeId = 1
        AND PQM.DerivedEngagementScore > 120
        AND PQM.CodeBlockHeuristic > 1 -- Questions with at least two code blocks
        AND PQM.UniqueEditorsCount > 2 -- Edited by at least two unique users
        AND UAS.ReputationTier IN ('Diamond Tier', 'Platinum Tier', 'Gold Tier')
        AND (PQM.CleanedTagsString LIKE '%sql%' OR PQM.CleanedTagsString LIKE '%database%')
        -- Exclude questions that have been deleted
        AND NOT EXISTS (
            SELECT 1 FROM PostHistory PH_deleted WHERE PH_deleted.PostId = PQM.PostId AND PH_deleted.PostHistoryTypeId = 12
        )
        -- Complex predicate combining NULL logic and string matching
        AND (PHD.CloseReasonId IS NULL OR PHD.CloseReasonId NOT IN (101, 102)) -- Not closed as Duplicate or Off-topic (current reasons)
        AND PQM.PostCreationDate > UAS.UserCreationDate + INTERVAL '3 months' -- Post must be after user's initial 3 months
)
UNION ALL
(
    -- Branch 2: Highly accepted answers from influential users, with context from their parent question
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.ReputationTier,
        UAS.UserCreationDate,
        UAS.UserLocation,
        PQM.PostId,
        'Answer' AS PostCategory,
        PQM.Title AS PostTitle, -- This will be NULL for answers, but maintain column for UNION ALL
        PQM.PostScore,
        -- ViewCount of the parent question for answers
        (SELECT Q.ViewCount FROM Posts Q WHERE Q.Id = PQM.ParentId) AS QuestionViewCount,
        PQM.DerivedEngagementScore,
        PQM.CodeBlockHeuristic,
        PQM.CleanedTagsString,
        NULL AS LatestCloseReason, -- Answers don't have close reasons associated with them directly
        NULL AS TotalBountyAmount, -- Answers do not typically initiate bounties
        -- Ratio of answer score to parent question's view count
        NULLIF(PQM.PostScore, 0)::NUMERIC / (SELECT NULLIF(Q.ViewCount, 0) FROM Posts Q WHERE Q.Id = PQM.ParentId) AS AnswerScoreToQuestionViewRatio,
        -- Rank answers by score within their reputation tier
        RANK() OVER (PARTITION BY UAS.ReputationTier ORDER BY PQM.PostScore DESC, PQM.PostCreationDate DESC) AS RankWithinTier,
        'Highly Accepted Answer Analysis' AS AnalysisType,
        NULL AS LatestCloseReasonId,
        EXTRACT(HOUR FROM (PQM.PostCreationDate - PQM.PreviousPostDate)) AS HoursSincePreviousPost
    FROM UserActivitySummary AS UAS
    INNER JOIN PostQualityMetrics AS PQM ON UAS.UserId = PQM.OwnerUserId
    -- Ensure the answer is actually accepted by its parent question
    INNER JOIN Posts AS AcceptedQuestion ON PQM.ParentId = AcceptedQuestion.Id AND AcceptedQuestion.AcceptedAnswerId = PQM.Id
    WHERE
        PQM.PostTypeId = 2
        AND PQM.PostScore > 75 -- Only highly scored answers
        AND PQM.CreationDate > UAS.UserCreationDate + INTERVAL '6 months' -- Answer must be posted after user's first 6 months
        AND UAS.ReputationTier IN ('Diamond Tier', 'Platinum Tier', 'Gold Tier')
        AND (PQM.CleanedTagsString LIKE '%javascript%' OR PQM.CleanedTagsString LIKE '%frontend%')
        -- Check for existence of a 'thank you' comment on the answer
        AND EXISTS (
            SELECT 1 FROM Comments C_inner WHERE C_inner.PostId = PQM.PostId AND LOWER(C_inner.Text) LIKE '%thank%'
        )
        -- Further complex string expression check
        AND LENGTH(TRIM(COALESCE(PQM.Body, ''))) > 200
)
ORDER BY
    Reputation DESC,
    DerivedEngagementScore DESC NULLS LAST,
    AnalysisType ASC,
    PostCategory DESC
LIMIT 250 OFFSET 50;
