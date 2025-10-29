-- {"query": "1988.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2626} 

WITH UserActivityMetrics AS (
    -- Calculate aggregated metrics for each user, including post counts, scores, badge counts, and a summary of their tags.
    -- This CTE identifies core user activity and influence.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsByOwner,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersByOwner,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreByOwner,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0.0) AS AvgQuestionScoreByOwner,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0) AS TotalAnswerScoreByOwner,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        -- Aggregate distinct tags from their questions, limited to 100 characters for brevity.
        -- Uses string manipulation and aggregation for a complex string expression.
        SUBSTRING(
            STRING_AGG(DISTINCT s.tag_name, ',' ORDER BY s.tag_name)
                FILTER (WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2),
            1, 100
        ) AS TopQuestionTagsSummary
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    -- Lateral join to parse tags from the 'Tags' string using `string_to_array` and `UNNEST`.
    -- This effectively treats the 'Tags' string as an array and unrolls it for aggregation.
    LEFT JOIN LATERAL (
        SELECT TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS tag_name
        WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    ) s ON TRUE
    WHERE U.Id IS NOT NULL -- Ensure we are looking at actual users, excluding null OwnerUserId cases
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) >= 1 -- Only users who have asked at least one question
),
RankedClosedQuestionAnalysis AS (
    -- Identifies all instances of questions being closed, focusing on specific close reasons.
    -- Applies a row number to find the most recent closure for each user's questions.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.Title AS QuestionTitle,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        PH.CreationDate AS ClosureHistoryDate,
        CR.Name AS CloseReasonTypeName,
        -- Calculate time difference between question creation and closure in hours using date arithmetic.
        EXTRACT(EPOCH FROM (PH.CreationDate - P.CreationDate)) / 3600 AS TimeToClosureHours,
        -- Extract potential original question IDs from the PostHistory.Text JSON string using a regex.
        -- `COALESCE` and `NULLIF` handle cases where the pattern might not match or Text is NULL/empty.
        COALESCE(
            NULLIF(SUBSTRING(PH.Text FROM '"OriginalQuestionIds":\[(\d+(?:,\s*\d+)*)\]'), ''),
            'N/A'
        ) AS OriginalDuplicateQuestionIds,
        -- Correlated subquery to count edits on the question before it was closed.
        (
            SELECT COUNT(ph_edit.Id)
            FROM PostHistory ph_edit
            WHERE ph_edit.PostId = P.Id
              AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
              AND ph_edit.CreationDate < PH.CreationDate
        ) AS EditsBeforeClosureCount,
        -- Find the display name of the most recent editor before closure, handling NULLs gracefully.
        -- Uses a subquery and COALESCE.
        COALESCE(
            (SELECT U_editor.DisplayName FROM Users U_editor WHERE U_editor.Id = P.LastEditorUserId),
            'Community or Unknown'
        ) AS LastEditorDisplayNameBeforeClosure,
        -- Window function to rank closure events for each user's questions by creation date descending.
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY PH.CreationDate DESC) AS rn
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    -- Robust conversion of PH.Comment to SMALLINT for joining with CloseReasonTypes, handling non-numeric strings with CASE.
    LEFT JOIN CloseReasonTypes CR ON
        (CASE WHEN PH.Comment ~ '^[0-9]+$' THEN CAST(PH.Comment AS SMALLINT) ELSE NULL END) = CR.Id
    WHERE
        P.PostTypeId = 1 -- Only considering questions
        AND PH.PostHistoryTypeId = 10 -- Post Closed event
        AND (CR.Name LIKE '%Duplicate%' OR CR.Name LIKE '%Off-topic%' OR CR.Name LIKE '%Needs more focus%') -- Broader close reasons
        AND P.OwnerUserId IS NOT NULL -- Exclude community-owned or deleted user posts
),
ClosedQuestionAnalysis AS (
    -- Filters the ranked closures to get only the most recent closed question for each user.
    SELECT *
    FROM RankedClosedQuestionAnalysis
    WHERE rn = 1
),
TopAnswerPerUser AS (
    -- Identifies the single top-scoring answer for each user.
    SELECT
        A.OwnerUserId AS UserId,
        A.Id AS AnswerId,
        A.ParentId AS QuestionIdAnswered,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        -- Window function to rank answers by score for each user.
        ROW_NUMBER() OVER (PARTITION BY A.OwnerUserId ORDER BY A.Score DESC, A.CreationDate DESC) AS AnswerRank
    FROM Posts A
    WHERE A.PostTypeId = 2 -- Only answers
      AND A.OwnerUserId IS NOT NULL
      AND A.Score >= 10 -- Only consider highly upvoted answers
),
ReputationTieredUsers AS (
    -- Categorize users into reputation tiers using NTILE for comparative analysis.
    -- Also calculates the reputation difference from the previous user in rank using LAG.
    SELECT
        UserId,
        Reputation,
        NTILE(5) OVER (ORDER BY Reputation DESC) AS ReputationTier, -- Divide users into 5 tiers by reputation
        LAG(Reputation, 1, 0) OVER (ORDER BY Reputation DESC) AS PrevUserReputation, -- Reputation of the user immediately above in rank
        Reputation - LAG(Reputation, 1, 0) OVER (ORDER BY Reputation DESC) AS RepDifferenceFromPrev
    FROM UserActivityMetrics
    WHERE TotalQuestionsByOwner > 0 AND TotalAnswersByOwner > 0
)
-- Main query: Combines all CTEs to find influential users with specific closed questions and highly-rated answers.
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    RTU.ReputationTier,
    RTU.RepDifferenceFromPrev,
    UAM.GoldBadges,
    UAM.SilverBadges,
    UAM.TotalQuestionsByOwner,
    UAM.TotalAnswersByOwner,
    UAM.AvgQuestionScoreByOwner,
    UAM.TotalAnswerScoreByOwner,
    CQ.QuestionTitle AS LastClosedQuestionTitle,
    CQ.ClosureHistoryDate AS LastClosedQuestionDate,
    CQ.CloseReasonTypeName AS LastClosedQuestionReason,
    CQ.TimeToClosureHours AS LastClosedQuestionTimeToClosureHours,
    CQ.EditsBeforeClosureCount AS LastClosedQuestionEditsBeforeClosure,
    CQ.LastEditorDisplayNameBeforeClosure,
    CQ.OriginalDuplicateQuestionIds,
    TA.AnswerId AS TopAnswerId,
    TA.AnswerScore AS TopAnswerScore,
    TA.QuestionIdAnswered AS QuestionForTopAnswerId,
    UAM.TopQuestionTagsSummary AS UserQuestionTags,
    -- Complicated calculation: Ratio of total answer score to total question score,
    -- handling division by zero and NULLs using `COALESCE` and `NULLIF`.
    COALESCE(
        NULLIF(CAST(UAM.TotalAnswerScoreByOwner AS DECIMAL), 0) / NULLIF(CAST(UAM.TotalQuestionScoreByOwner AS DECIMAL), 0),
        0.0
    ) AS AnswerToQuestionScoreRatio,
    -- Complicated predicate/expression: Check if user's 'AboutMe' contains specific keywords, case-insensitively.
    CASE
        WHEN U.AboutMe ILIKE '%performance%' OR U.AboutMe ILIKE '%optimization%' OR U.AboutMe ILIKE '%scaling%' THEN TRUE
        ELSE FALSE
    END AS MentionsPerformanceOrOptimizationInAboutMe,
    -- Correlated subquery in SELECT clause: Count how many times the user has cast a 'Close' vote.
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.UserId = UAM.UserId AND V.VoteTypeId = 6) AS TotalCloseVotesCastByThisUser
FROM UserActivityMetrics UAM
JOIN ReputationTieredUsers RTU ON UAM.UserId = RTU.UserId -- Join to get reputation tier data
LEFT JOIN ClosedQuestionAnalysis CQ ON UAM.UserId = CQ.OwnerUserId -- Left join to include users even if they don't have a *recently* closed question
LEFT JOIN TopAnswerPerUser TA ON UAM.UserId = TA.UserId AND TA.AnswerRank = 1 -- Left join for top answer
LEFT JOIN Users U ON UAM.UserId = U.Id -- Re-join Users to access the AboutMe column
WHERE
    (UAM.GoldBadges >= 1 OR UAM.SilverBadges >= 2) -- Filter for influential users based on badge class
    AND UAM.TotalQuestionsByOwner >= 5 -- User must have asked a significant number of questions
    AND UAM.TotalAnswersByOwner >= 3 -- User must have provided a significant number of answers
    AND CQ.QuestionId IS NOT NULL -- Must have at least one closed question matching the criteria
    AND TA.AnswerId IS NOT NULL -- Must have at least one top answer
    -- Exclude users whose display name looks like a bot or generic account using string matching.
    AND UAM.DisplayName IS NOT NULL
    AND UAM.DisplayName NOT ILIKE '%bot%'
    AND UAM.DisplayName NOT ILIKE '%guest%'
    AND UAM.DisplayName NOT ILIKE '%deleted%'
ORDER BY
    UAM.Reputation DESC,
    UAM.GoldBadges DESC,
    UAM.SilverBadges DESC,
    CQ.TimeToClosureHours ASC NULLS LAST -- Sort by time to closure, placing NULLs (no recent closed question) last
LIMIT 100;
