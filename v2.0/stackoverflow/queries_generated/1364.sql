-- {"query": "1364.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2851} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user activity, calculate reputation tiers and NTILE for benchmarking various aggregation and window function patterns.
    -- Includes LEFT JOIN to handle users with no posts, though filtered later.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) AS AvgContentScore,
        MAX(P.LastActivityDate) AS LastActivityOnPost,
        NTILE(4) OVER (ORDER BY U.Reputation DESC) AS ReputationQuartile,
        CASE
            WHEN U.Reputation >= 100000 THEN 'Legendary'
            WHEN U.Reputation >= 20000 THEN 'Veteran'
            WHEN U.Reputation >= 1000 THEN 'Contributor'
            ELSE 'Novice'
        END AS ReputationTier
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 -- Focus on active users
),
UserBadgeSummary AS (
    -- CTE 2: Summarize user badges, focusing on Gold badges for eligibility criteria.
    SELECT
        UserId,
        COUNT(Id) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
PostDetails AS (
    -- CTE 3: Extend question post information with comment aggregates, accepted answer details, and editing activity.
    -- Uses multiple LEFT JOINs and aggregates with FILTER clauses.
    SELECT
        PQ.Id AS QuestionId,
        PQ.OwnerUserId AS QuestionOwnerId,
        PQ.Title AS QuestionTitle,
        PQ.Body AS QuestionBody, -- Included for complex predicate
        PQ.CreationDate AS QuestionCreationDate,
        PQ.Score AS QuestionScore,
        PQ.ViewCount,
        COALESCE(PQ.AnswerCount, 0) AS AnswerCount,
        COALESCE(PQ.FavoriteCount, 0) AS FavoriteCount,
        PQ.ClosedDate,
        PQ.Tags,
        PA.Id AS AcceptedAnswerId,
        PA.CreationDate AS AcceptedAnswerCreationDate,
        PA.Score AS AcceptedAnswerScore,
        COALESCE(SUM(CASE WHEN PC.PostId = PQ.Id THEN 1 ELSE 0 END), 0) AS QuestionCommentCount,
        COALESCE(AVG(CASE WHEN PC.PostId = PQ.Id THEN PC.Score ELSE NULL END), 0.0) AS AvgQuestionCommentScore,
        MAX(PH_Edit.CreationDate) FILTER (WHERE PH_Edit.PostHistoryTypeId IN (4,5,6)) AS LastEditDate,
        COUNT(PH_Edit.Id) FILTER (WHERE PH_Edit.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        MIN(PH_Edit.CreationDate) FILTER (WHERE PH_Edit.PostHistoryTypeId IN (4,5,6)) AS FirstEditDate
    FROM Posts AS PQ -- Question Posts
    LEFT JOIN Posts AS PA ON PQ.AcceptedAnswerId = PA.Id -- Accepted Answers
    LEFT JOIN Comments AS PC ON PQ.Id = PC.PostId
    LEFT JOIN PostHistory AS PH_Edit ON PQ.Id = PH_Edit.PostId
    WHERE PQ.PostTypeId = 1
    GROUP BY
        PQ.Id, PQ.OwnerUserId, PQ.Title, PQ.Body, PQ.CreationDate, PQ.Score, PQ.ViewCount, PQ.AnswerCount,
        PQ.FavoriteCount, PQ.ClosedDate, PQ.Tags, PA.Id, PA.CreationDate, PA.Score
),
PostClosureEvents AS (
    -- CTE 4: Gather all relevant post history events for closure and reopening.
    -- Uses ROW_NUMBER to identify the latest events for later aggregation.
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PH.Comment AS EventComment,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) AS rn_latest_event -- Latest per event type
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11) -- 10=Post Closed, 11=Post Reopened
),
PostClosureHistory AS (
    -- CTE 5: Consolidate post closure/reopening history and identify the last close reason.
    -- Uses a regular expression check before casting for robustness and NULL logic.
    SELECT
        PCE.PostId,
        MAX(CASE WHEN PCE.PostHistoryTypeId = 10 THEN PCE.EventDate ELSE NULL END) AS ClosedDateHist,
        MAX(CASE WHEN PCE.PostHistoryTypeId = 11 THEN PCE.EventDate ELSE NULL END) AS ReopenedDateHist,
        COUNT(CASE WHEN PCE.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEventCount,
        COUNT(CASE WHEN PCE.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEventCount,
        MAX(CASE WHEN PCE.PostHistoryTypeId = 10 AND PCE.rn_latest_event = 1 THEN PCE.EventComment ELSE NULL END) AS LastCloseReasonComment_Raw
    FROM PostClosureEvents AS PCE
    GROUP BY PCE.PostId
),
PostClosureReasonMapped AS (
    -- CTE 6: Map the raw close reason comment to the CloseReasonTypes table.
    -- Example of complex NULL handling and string pattern matching before explicit CAST.
    SELECT
        PCH.PostId,
        PCH.ClosedDateHist,
        PCH.ReopenedDateHist,
        PCH.CloseEventCount,
        PCH.ReopenEventCount,
        PCH.LastCloseReasonComment_Raw,
        CRT.Name AS LastCloseReasonName
    FROM PostClosureHistory AS PCH
    LEFT JOIN CloseReasonTypes AS CRT
        ON PCH.LastCloseReasonComment_Raw IS NOT NULL
        AND PCH.LastCloseReasonComment_Raw ~ '^[0-9]+$' -- PostgreSQL specific regex for numeric check
        AND CAST(PCH.LastCloseReasonComment_Raw AS smallint) = CRT.Id
),
TopQuestionTags AS (
    -- CTE 7: Extract and rank top tags for each question based on overall tag usage count.
    -- Uses UNNEST for array expansion and ROW_NUMBER for ranking.
    SELECT
        PD.QuestionId,
        PD.QuestionOwnerId,
        PD.QuestionScore,
        TRIM(UNNEST(string_to_array(SUBSTRING(PD.Tags, 2, LENGTH(PD.Tags)-2), '><'))) AS TagName,
        ROW_NUMBER() OVER (PARTITION BY PD.QuestionId ORDER BY T.Count DESC, T.TagName) AS TagRank
    FROM PostDetails AS PD
    JOIN Tags AS T ON TRIM(UNNEST(string_to_array(SUBSTRING(PD.Tags, 2, LENGTH(PD.Tags)-2), '><'))) = T.TagName
    WHERE PD.Tags IS NOT NULL AND LENGTH(PD.Tags) > 2
)
-- Main query: Combines all CTEs to analyze high-impact users with complex post and badge criteria.
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationTier,
    UBS.GoldBadges,
    PD.QuestionId,
    PD.QuestionTitle,
    PD.QuestionCreationDate,
    PD.QuestionScore,
    PD.AcceptedAnswerId,
    PD.AcceptedAnswerCreationDate,
    PD.AcceptedAnswerScore,
    PD.AnswerCount,
    PD.FavoriteCount,
    PD.ViewCount,
    PD.EditCount,
    EXTRACT(EPOCH FROM (PD.LastEditDate - PD.FirstEditDate)) / 3600.0 AS HoursBetweenFirstAndLastEdit, -- Complex date calculation
    PD.QuestionCommentCount,
    PD.AvgQuestionCommentScore,
    PCRM.ClosedDateHist AS ActualClosedDate,
    PCRM.ReopenedDateHist AS ActualReopenedDate,
    PCRM.LastCloseReasonName,
    COALESCE(LT.Name, 'NoLinkedQuestion') AS LinkTypeName, -- NULL logic using COALESCE
    LAG(PD.QuestionScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY PD.QuestionCreationDate) AS PreviousQuestionScore, -- Window function
    CASE
        WHEN PD.AcceptedAnswerId IS NOT NULL AND PD.AcceptedAnswerCreationDate IS NOT NULL AND PD.QuestionCreationDate IS NOT NULL THEN
            EXTRACT(EPOCH FROM (PD.AcceptedAnswerCreationDate - PD.QuestionCreationDate)) / 3600.0 -- Time to accepted answer in hours
        ELSE NULL
    END AS TimeToAcceptedAnswerHours,
    (SELECT AVG(TQS_Inner.QuestionScore) FROM TopQuestionTags AS TQS_Inner WHERE TQS_Inner.TagName = TQT_Primary.TagName) AS AvgTagScoreOverall, -- Correlated subquery
    STRING_AGG(TQT_Primary.TagName, ', ') FILTER (WHERE TQT_Primary.TagRank <= 3) AS Top3QuestionTags, -- String aggregation with filter
    (UE.UpVotes + UE.DownVotes) AS TotalVotesGivenByOwner, -- Simple calculation
    NULLIF(UE.UpVotes, 0) / NULLIF(UE.DownVotes, 0) AS UpVoteToDownVoteRatio, -- NULLIF for division by zero
    UE.TotalQuestions - UE.TotalAnswers AS QuestionAnswerDelta
FROM UserEngagement AS UE
INNER JOIN UserBadgeSummary AS UBS ON UE.UserId = UBS.UserId
LEFT JOIN PostDetails AS PD ON UE.UserId = PD.QuestionOwnerId
LEFT JOIN PostClosureReasonMapped AS PCRM ON PD.QuestionId = PCRM.PostId
LEFT JOIN PostLinks AS PL ON PD.QuestionId = PL.PostId AND PL.LinkTypeId = 1 -- Linked questions
LEFT JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
LEFT JOIN TopQuestionTags AS TQT_Primary ON PD.QuestionId = TQT_Primary.QuestionId AND TQT_Primary.TagRank = 1
WHERE
    UE.Reputation >= 10000 AND UBS.GoldBadges >= 1 -- High-reputation users with at least one gold badge
    AND PD.QuestionId IS NOT NULL -- Ensures only questions are considered (implicit from PostDetails)
    AND (PCRM.CloseEventCount > 0 AND PCRM.ReopenEventCount > 0) -- Questions that were closed AND reopened
    AND (PD.QuestionScore > 10 OR PD.FavoriteCount > 2) -- Interesting questions criteria
    AND (PD.QuestionTitle ILIKE '%sql%' OR PD.QuestionTitle ILIKE '%performance%') -- String expression, ILIKE for case-insensitivity
    AND PD.LastEditDate IS NOT NULL -- Question has been edited
    AND UE.DisplayName IS NOT NULL AND UE.DisplayName != '' -- Ensure display name exists and is not empty
    AND LENGTH(PD.QuestionBody) > 500 -- Complicated predicate: long questions
    AND NOT EXISTS (
        -- Correlated subquery: check if any of their recent comments contained a hypothetical "offensive" term
        SELECT 1
        FROM Comments AS C
        WHERE C.UserId = UE.UserId
          AND C.CreationDate > (NOW() - INTERVAL '1 year')
          AND C.Text ILIKE '%offensive%'
    )
ORDER BY
    UE.Reputation DESC,
    PD.QuestionScore DESC,
    TimeToAcceptedAnswerHours ASC NULLS LAST; -- NULLS LAST for order preference
