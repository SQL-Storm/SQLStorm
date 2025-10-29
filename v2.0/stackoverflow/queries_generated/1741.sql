-- {"query": "1741.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3144} 

WITH CriticalTags AS (
    -- Define a set of 'critical' tags, potentially using a combination of direct names and patterns.
    -- This CTE uses UNION ALL as a set operator example within the overall query.
    SELECT TagName FROM Tags WHERE TagName IN ('sql', 'database', 'performance', 'optimization', 'indexing')
    UNION ALL
    SELECT TagName FROM Tags WHERE TagName LIKE 'query%' AND TagName NOT IN ('query-string')
),
UserContributionSummary AS (
    -- Summarize key metrics for users with a significant presence.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P_Owned.Id) AS TotalOwnedPosts,
        SUM(CASE WHEN P_Owned.PostTypeId = 1 THEN 1 ELSE 0 END) AS OwnedQuestions,
        SUM(CASE WHEN P_Owned.PostTypeId = 2 THEN 1 ELSE 0 END) AS OwnedAnswers,
        SUM(CASE WHEN P_Owned.PostTypeId = 1 AND P_Owned.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS OwnedClosedQuestions
    FROM Users U
    LEFT JOIN Posts P_Owned ON U.Id = P_Owned.OwnerUserId
    WHERE U.Reputation >= 1000 AND U.Views > 50
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P_Owned.Id) > 5 -- Ensure at least 5 owned posts for filtering
),
QuestionTagAnalysis AS (
    -- Identify questions related to critical tags and aggregate their initial performance.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerId,
        P.CreationDate AS QuestionCreationDate,
        P.ViewCount,
        P.Score AS QuestionScore,
        P.Title AS QuestionTitle,
        ARRAY_AGG(DISTINCT CT.TagName) FILTER (WHERE CT.TagName IS NOT NULL) AS QuestionCriticalTags,
        COUNT(DISTINCT P_Ans.Id) AS AnswerCount,
        SUM(COALESCE(P_Ans.Score, 0)) AS TotalAnswerScore,
        AVG(COALESCE(P_Ans.Score, 0)) AS AvgAnswerScore
    FROM Posts P
    LEFT JOIN Posts P_Ans ON P.Id = P_Ans.ParentId AND P_Ans.PostTypeId = 2
    LEFT JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName
    ) AS TagList ON TRUE
    INNER JOIN CriticalTags CT ON TagList.TagName = CT.TagName
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.ViewCount, P.Score, P.Title
    HAVING COUNT(DISTINCT CT.TagName) >= 1
),
AnswerEditHistory AS (
    -- Analyze the edit history of answers, specifically looking for accepted answers and significant changes.
    SELECT
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.ParentId AS QuestionId,
        COUNT(PH.Id) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate,
        -- Detect "fix" or "resolve" keywords in post history text, indicative of corrections.
        SUM(CASE WHEN PH.Text ILIKE '%fix%' OR PH.Text ILIKE '%resolve%' THEN 1 ELSE 0 END) AS FixRelatedEdits,
        -- Use LAG window function to calculate time between consecutive edits.
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1) OVER (PARTITION BY A.Id ORDER BY PH.CreationDate))) / 3600 AS HoursSincePrevEdit
    FROM Posts A
    INNER JOIN PostHistory PH ON A.Id = PH.PostId AND PH.PostHistoryTypeId IN (5, 8) -- Body Edits/Rollbacks
    WHERE A.PostTypeId = 2
    GROUP BY A.Id, A.OwnerUserId, A.CreationDate, A.Score, A.ParentId
),
ProblematicQuestionMetrics AS (
    -- Identify questions with high edit counts or multiple close/reopen cycles, and rank them per owner.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerId,
        P.Title AS ProblemQuestionTitle,
        COUNT(PH_Edit.Id) AS TotalEdits,
        SUM(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        MAX(PH_Close.CreationDate) AS LastCloseDate,
        ARRAY_AGG(DISTINCT CRT.Name) FILTER (WHERE CRT.Name IS NOT NULL) AS AllCloseReasons,
        -- Rank problematic questions for each user based on edit count and close events.
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(PH_Edit.Id) DESC, SUM(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) DESC) AS Rnk_Problem
    FROM Posts P
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CRT ON PH_Close.Comment::smallint = CRT.Id AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.OwnerUserId, P.Title
    HAVING COUNT(PH_Edit.Id) > 3 OR SUM(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) > 0
),
RecentGoldSilverBadges AS (
    -- Find the most recent Gold or Silver badge for users, excluding non-technical categories.
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Date AS BadgeAwardDate,
        B.Class,
        -- Rank badges by date for each user to pick the most recent.
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS rn
    FROM Badges B
    WHERE B.Class IN (1, 2) -- Gold or Silver badges
      AND B.Date >= NOW() - INTERVAL '1 year' -- Awarded in the last year
      AND B.Name NOT ILIKE '%voting%' AND B.Name NOT ILIKE '%commenter%' -- Exclude non-tech engagement badges
      AND B.Name IN (SELECT DISTINCT Name FROM Badges WHERE TagBased = TRUE) -- Filter for potentially tag-based (technical) badges
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes,
    U.DownVotes,
    -- General user performance metrics using window functions
    RANK() OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS OverallUserRank,
    DENSE_RANK() OVER (PARTITION BY U.Location ORDER BY U.Reputation DESC) AS RankInLocation,
    NTILE(5) OVER (ORDER BY QTA.ViewCount DESC, AEH_MaxEdit.EditCount DESC) AS TopInfluencerTier, -- Categorize into 5 tiers
    U.CreationDate,
    U.LastAccessDate,
    U.Location,
    -- Correlated subquery: average score of all answers by this user
    (SELECT AVG(SubQ.Score) FROM Posts SubQ WHERE SubQ.OwnerUserId = U.Id AND SubQ.PostTypeId = 2 AND SubQ.CreationDate >= U.CreationDate AND SubQ.CreationDate <= U.LastAccessDate) AS AvgAnswerScoreByThisUser,
    -- Details of the most influential question (high views, critical tags)
    QTA.QuestionId AS InfluentialQuestionId,
    QTA.QuestionTitle,
    QTA.QuestionCriticalTags,
    QTA.ViewCount AS QuestionViewCount,
    QTA.QuestionScore,
    -- Details of the accepted answer for the influential question, with edit metrics
    AEH_MaxEdit.AnswerId AS AcceptedAnswerId,
    AEH_MaxEdit.AnswerScore AS AcceptedAnswerScore,
    AEH_MaxEdit.EditCount AS AcceptedAnswerEditCount,
    AEH_MaxEdit.FixRelatedEdits AS AcceptedAnswerFixEdits,
    AEH_MaxEdit.HoursSincePrevEdit AS AcceptedAnswerHoursSincePrevEdit,
    -- Details of the most problematic question owned by the user
    PQ.QuestionId AS MostProblematicQuestionId,
    PQ.ProblemQuestionTitle,
    PQ.TotalEdits AS ProblematicQuestionTotalEdits,
    PQ.CloseEvents AS ProblematicQuestionCloseEvents,
    PQ.ReopenEvents AS ProblematicQuestionReopenEvents,
    PQ.AllCloseReasons AS ProblematicQuestionCloseReasons,
    -- Most recent Gold/Silver badge details
    COALESCE(RGB.BadgeName, 'No Recent Gold/Silver') AS MostRecentNotableBadge,
    COALESCE(RGB.BadgeAwardDate, U.CreationDate) AS MostRecentBadgeDate,
    -- Complex expressions and NULL logic
    CASE
        WHEN U.UpVotes > U.DownVotes * 5 AND AEH_MaxEdit.EditCount > 3 AND QTA.QuestionScore > 100 THEN 'Elite & Prolific Contributor'
        WHEN U.UpVotes > U.DownVotes * 2 AND AEH_MaxEdit.EditCount > 1 THEN 'Valued & Active Contributor'
        WHEN U.Reputation > 10000 THEN 'High Reputation Contributor'
        ELSE 'General Contributor'
    END AS ContributorCategory,
    ABS(U.UpVotes - U.DownVotes) AS VoteDifference,
    REPLACE(REPLACE(REPLACE(U.Location, 'United States', 'USA'), 'United Kingdom', 'UK'), 'England', 'UK') AS SimplifiedLocation,
    NULLIF(LENGTH(U.AboutMe), 0) AS AboutMeLength, -- Length of AboutMe, NULL if empty
    (EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 3600 / 24 / 365.25)::numeric(5,2) AS YearsActive -- User tenure
FROM Users U
INNER JOIN UserContributionSummary UCS ON U.Id = UCS.UserId -- Filter for active users
LEFT JOIN (
    -- Subquery to select the top-viewed critical question for each influential user.
    SELECT
        QTA_Sub.QuestionId,
        QTA_Sub.QuestionOwnerId,
        QTA_Sub.QuestionTitle,
        QTA_Sub.ViewCount,
        QTA_Sub.QuestionScore,
        QTA_Sub.QuestionCriticalTags,
        ROW_NUMBER() OVER (PARTITION BY QTA_Sub.QuestionOwnerId ORDER BY QTA_Sub.ViewCount DESC, QTA_Sub.QuestionScore DESC) AS rn_q
    FROM QuestionTagAnalysis QTA_Sub
) AS QTA ON U.Id = QTA.QuestionOwnerId AND QTA.rn_q = 1
LEFT JOIN (
    -- Subquery to find the most edited accepted answer for the influential question, if any.
    SELECT
        AEH_Sub.AnswerId,
        AEH_Sub.AnswerOwnerId,
        AEH_Sub.AnswerScore,
        AEH_Sub.QuestionId,
        AEH_Sub.EditCount,
        AEH_Sub.FixRelatedEdits,
        AEH_Sub.HoursSincePrevEdit,
        ROW_NUMBER() OVER (PARTITION BY AEH_Sub.AnswerOwnerId, AEH_Sub.QuestionId ORDER BY AEH_Sub.EditCount DESC, AEH_Sub.AnswerScore DESC) AS rn_a
    FROM AnswerEditHistory AEH_Sub
    INNER JOIN Posts P_Ans_Accepted ON AEH_Sub.AnswerId = P_Ans_Accepted.Id AND P_Ans_Accepted.AcceptedAnswerId IS NOT NULL
) AS AEH_MaxEdit ON U.Id = AEH_MaxEdit.AnswerOwnerId AND QTA.QuestionId = AEH_MaxEdit.QuestionId AND AEH_MaxEdit.rn_a = 1
LEFT JOIN ProblematicQuestionMetrics PQ ON U.Id = PQ.QuestionOwnerId AND PQ.Rnk_Problem = 1
LEFT JOIN RecentGoldSilverBadges RGB ON U.Id = RGB.UserId AND RGB.rn = 1
WHERE U.Reputation > 5000 AND U.Views > 500
  AND QTA.QuestionId IS NOT NULL -- Must have an influential question related to critical tags
  AND AEH_MaxEdit.AnswerId IS NOT NULL -- Must have an accepted answer to that influential question
  AND AEH_MaxEdit.EditCount >= 2 -- Accepted answer must have been edited at least twice
ORDER BY OverallUserRank ASC, QuestionViewCount DESC, AcceptedAnswerEditCount DESC
LIMIT 100;
