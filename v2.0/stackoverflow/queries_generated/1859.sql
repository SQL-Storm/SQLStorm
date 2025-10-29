-- {"query": "1859.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3155} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAuthored,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersAuthored,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        U.UpVotes AS TotalUpvotesGiven,
        U.DownVotes AS TotalDownvotesGiven,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LatestActivityForUser,
        -- Calculate a weighted engagement score based on various user metrics
        (U.Reputation * 0.1
         + SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount * 0.0005 ELSE 0 END)
         + SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score * 0.25 ELSE 0 END)
         + COUNT(DISTINCT B.Id) * 5 -- Each unique badge contributes to engagement
        ) AS WeightedEngagementScore
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.Tags,
        P.ClosedDate,
        P.CommunityOwnedDate,
        -- Count distinct users who edited the post's title, body, or tags
        COUNT(DISTINCT PH_Edit.UserId) FILTER (WHERE PH_Edit.PostHistoryTypeId IN (4, 5, 6)) AS NumberOfUniqueEditors,
        -- Find the latest closure and reopening dates from post history
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN PH_Close.CreationDate END) AS LatestCloseDate,
        MAX(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN PH_Reopen.CreationDate END) AS LatestReopenDate,
        -- Identify migration events
        MAX(CASE WHEN PH_MigrateAway.PostHistoryTypeId = 35 THEN PH_MigrateAway.CreationDate END) AS MigratedAwayDate,
        MAX(CASE WHEN PH_MigrateHere.PostHistoryTypeId = 36 THEN PH_MigrateHere.CreationDate END) AS MigratedHereDate,
        -- Determine the display name of the last editor, defaulting to 'Community' if not available
        COALESCE(P.LastEditorDisplayName, 'Community') AS LastKnownEditorDisplayName,
        -- Correlated subquery: Get the highest score among all comments for this post
        (SELECT COALESCE(MAX(C_sub.Score), 0) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS MaxCommentScore,
        -- Correlated subquery: Check if any answer to this question has a very high score (e.g., > 75)
        EXISTS (
            SELECT 1 FROM Posts A_sub WHERE A_sub.ParentId = P.Id AND A_sub.PostTypeId = 2 AND A_sub.Score > 75
        ) AS HasHighlyScoredAnswer,
        -- Correlated subquery: Calculate the average score of all answers associated with this question
        (SELECT AVG(A_sub.Score) FROM Posts A_sub WHERE A_sub.ParentId = P.Id AND A_sub.PostTypeId = 2) AS AverageAnswerScore,
        -- String expression: Check if the post's tags contain 'sql' or 'database' (case-insensitive)
        (P.Tags ILIKE '%<sql>%' OR P.Tags ILIKE '%<database>%') AS ContainsSQLOrDatabaseTag
    FROM
        Posts P
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_MigrateAway ON P.Id = PH_MigrateAway.PostId AND PH_MigrateAway.PostHistoryTypeId = 35
    LEFT JOIN PostHistory PH_MigrateHere ON P.Id = PH_MigrateHere.PostId AND PH_MigrateHere.PostHistoryTypeId = 36
    WHERE P.PostTypeId = 1 -- Focus exclusively on questions
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.Tags, P.ClosedDate, P.CommunityOwnedDate, P.LastEditorDisplayName
),
TagPerformanceStats AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(P.Id) AS TagQuestionCount,
        AVG(P.Score) AS TagAverageScore,
        SUM(P.ViewCount) AS TagTotalViewCount,
        -- Calculate the percentage of questions for this tag that have been closed
        SUM(CASE WHEN P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END)::NUMERIC / COUNT(P.Id) AS TagClosureRate
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))
),
RankedTagPerformance AS (
    SELECT
        TagName,
        TagQuestionCount,
        TagAverageScore,
        TagTotalViewCount,
        TagClosureRate,
        -- Rank tags based on question count and average score, breaking ties by total view count
        DENSE_RANK() OVER (ORDER BY TagQuestionCount DESC, TagAverageScore DESC, TagTotalViewCount DESC) AS TagPopularityRank
    FROM
        TagPerformanceStats
),
ModerationActionSequence AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId AS EventType,
        PH.UserId AS ActionUserId,
        PH.UserDisplayName AS ActionUserDisplayName,
        PH.Comment AS EventComment,
        -- Use LAG to get the creation date of the previous moderation event for the same post
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventDate,
        -- Custom category for close reasons, handling potential NULLs or generic comments
        COALESCE(NULLIF(SUBSTRING(PH.Comment FROM 1 FOR 50), ''), 'No specific reason given') AS SimplifiedCloseReason
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20, 35, 36) -- Close, Reopen, Delete, Undelete, Protect, Unprotect, Migrate Away/Here
)
-- Main query to find highly engaged users with impactful, moderation-affected questions
SELECT
    UE.DisplayName AS UserDisplayName,
    UE.Reputation AS UserReputation,
    UE.UserLocation,
    UE.WeightedEngagementScore,
    PHM.Title AS QuestionTitle,
    PHM.Score AS QuestionScore,
    PHM.ViewCount AS QuestionViewCount,
    PHM.AnswerCount AS NumberOfAnswers,
    PHM.NumberOfUniqueEditors AS QuestionUniqueEditorCount,
    PHM.HasHighlyScoredAnswer,
    PHM.AverageAnswerScore,
    PHM.MaxCommentScore,
    PHM.PostCreationDate,
    PHM.LatestCloseDate,
    PHM.LatestReopenDate,
    PHM.ContainsSQLOrDatabaseTag,
    PHM.LastKnownEditorDisplayName,
    RTP.TagName AS PrimaryAssociatedTag,
    RTP.TagPopularityRank,
    RTP.TagAverageScore,
    RTP.TagClosureRate,
    -- Calculate duration between close and reopen events in days, default to -1 if not applicable
    COALESCE(
        EXTRACT(DAY FROM (PHM.LatestReopenDate - PHM.LatestCloseDate)),
        -1.0
    ) AS DaysBetweenCloseAndReopen,
    -- Categorize users into tiers based on their reputation
    CASE
        WHEN UE.Reputation >= 200000 THEN 'Legendary Contributor'
        WHEN UE.Reputation >= 50000 THEN 'Distinguished Expert'
        WHEN UE.Reputation >= 10000 THEN 'Seasoned Pro'
        WHEN UE.Reputation >= 2500 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS UserReputationTier,
    -- Correlated subquery: Retrieve the text of the latest comment with a positive score for the question
    (SELECT
        C_latest.Text
    FROM
        Comments C_latest
    WHERE
        C_latest.PostId = PHM.PostId
        AND C_latest.Score > 0
    ORDER BY
        C_latest.CreationDate DESC
    LIMIT 1) AS LatestPositiveCommentText,
    -- Window function: Calculate the average score of all questions by the same user created in the same calendar year
    AVG(PHM.Score) OVER (PARTITION BY UE.UserId, EXTRACT(YEAR FROM PHM.PostCreationDate)) AS AvgQuestionScoreByUserInYear,
    -- Window function: Rank this question globally among all questions with similar tag characteristics by score
    RANK() OVER (PARTITION BY PHM.ContainsSQLOrDatabaseTag ORDER BY PHM.Score DESC, PHM.ViewCount DESC) AS GlobalTagContextScoreRank,
    -- Correlated subquery: Calculate the average time (in hours) between moderation events for this specific post
    (SELECT
        AVG(EXTRACT(EPOCH FROM (MAS_sub.EventDate - MAS_sub.PreviousEventDate)) / 3600.0)
    FROM
        ModerationActionSequence MAS_sub
    WHERE
        MAS_sub.PostId = PHM.PostId
        AND MAS_sub.EventDate > MAS_sub.PreviousEventDate
    ) AS AverageHoursBetweenModerationEvents,
    -- Boolean flag: True if the question was migrated away and then migrated back
    (PHM.MigratedAwayDate IS NOT NULL AND PHM.MigratedHereDate IS NOT NULL AND PHM.MigratedHereDate > PHM.MigratedAwayDate) AS WasMigratedAndReturned,
    -- Example of a complicated string expression: Extracting the first 20 characters of the title, uppercasing it, and appending user ID
    UPPER(SUBSTRING(PHM.Title FROM 1 FOR 20)) || '...' || (UE.UserId)::VARCHAR AS DerivedQuestionIdentifier
FROM
    UserEngagement UE
INNER JOIN
    PostHistoricalMetrics PHM ON UE.UserId = PHM.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join to find the top-ranked tag associated with the question
    SELECT
        RTP_sub.TagName,
        RTP_sub.TagPopularityRank,
        RTP_sub.TagAverageScore,
        RTP_sub.TagClosureRate
    FROM
        RankedTagPerformance RTP_sub
    WHERE
        PHM.Tags LIKE CONCAT('%<', RTP_sub.TagName, '>%' ) -- Matches tag names enclosed in <>
    ORDER BY
        RTP_sub.TagPopularityRank ASC, RTP_sub.TagQuestionCount DESC
    LIMIT 1
) RTP ON TRUE -- LATERAL JOIN allows referencing PHM from within its subquery
WHERE
    UE.Reputation > 5000 -- Filter for users with significant reputation
    AND PHM.Score > 75 -- Only consider questions with a high score
    AND PHM.PostTypeId = 1 -- Explicitly ensure questions (redundant but good for clarity)
    AND (PHM.LatestCloseDate IS NOT NULL OR PHM.AverageAnswerScore > 30) -- Questions that were closed OR have very high-scoring answers
    AND LENGTH(PHM.Title) BETWEEN 40 AND 180 -- Specific title length constraints
    AND PHM.NumberOfUniqueEditors >= 3 -- Questions edited by at least 3 distinct users
    AND PHM.MaxCommentScore >= 5 -- Only questions with at least one positively-scored comment
    AND (PHM.ContainsSQLOrDatabaseTag OR RTP.TagPopularityRank <= 50) -- Focus on specific tech tags or very popular ones
ORDER BY
    UE.WeightedEngagementScore DESC, PHM.QuestionScore DESC, DaysBetweenCloseAndReopen ASC NULLS LAST
LIMIT 10000;
