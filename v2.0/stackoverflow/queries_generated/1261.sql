-- {"query": "1261.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3989} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(P.Score, 0)) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        MAX(B.Date) AS LatestBadgeDate,
        -- Calculate the reputation tier
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationTier
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.Body,
        P.OwnerUserId,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        -- Extract first significant tag
        TRIM(SUBSTRING(P.Tags, POSITION('<' IN P.Tags) + 1, POSITION('>' IN P.Tags) - POSITION('<' IN P.Tags) - 1)) AS PrimaryTag,
        -- Calculate post age in months
        DATE_PART('year', AGE(NOW(), P.CreationDate)) * 12 + DATE_PART('month', AGE(NOW(), P.CreationDate)) AS PostAgeMonths,
        -- Check if post body mentions common performance keywords
        CASE
            WHEN P.Body ILIKE '%performance%' OR P.Body ILIKE '%optimization%' OR P.Body ILIKE '%latency%' THEN TRUE
            ELSE FALSE
        END AS MentionsPerformance,
        -- Calculate time difference between post creation and its first edit
        EXTRACT(EPOCH FROM (MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) - P.CreationDate)) / 3600 AS HoursToFirstEdit,
        -- Count unique users who edited the post
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL) AS UniqueEditors,
        -- Was the post ever reopened after being closed?
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN TRUE ELSE FALSE END) AS WasReopened
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.AcceptedAnswerId, P.ParentId, P.CreationDate, P.Score,
        P.ViewCount, P.Body, P.OwnerUserId, P.LastActivityDate, P.Title, P.Tags,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate
),
QuestionDerivedMetrics AS (
    SELECT
        Q.PostId AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerUserId,
        Q.PostCreationDate AS QuestionCreationDate,
        Q.PostScore AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.Title AS QuestionTitle,
        Q.PrimaryTag,
        Q.PostAgeMonths,
        Q.MentionsPerformance,
        Q.HoursToFirstEdit,
        Q.UniqueEditors,
        Q.WasReopened,
        Q.AcceptedAnswerId AS AcceptedAnswerPostId,
        A.PostId AS AnswerId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.PostScore AS AnswerScore,
        A.PostCreationDate AS AnswerCreationDate,
        -- Rank answers for each question based on score, then creation date
        ROW_NUMBER() OVER (PARTITION BY Q.PostId ORDER BY A.PostScore DESC, A.PostCreationDate DESC) AS AnswerScoreRank,
        -- Calculate the percentage of views that led to an answer
        COALESCE(CAST(Q.AnswerCount AS NUMERIC) / NULLIF(Q.ViewCount, 0) * 100, 0) AS ViewToAnswerRatio,
        -- For accepted answer, calculate time to acceptance
        EXTRACT(EPOCH FROM (PD_AA.PostCreationDate - Q.PostCreationDate)) / (24 * 3600) AS DaysToAcceptance
    FROM PostHistoricalMetrics AS Q
    LEFT JOIN PostHistoricalMetrics AS A ON Q.PostId = A.ParentId AND A.PostTypeId = 2
    LEFT JOIN PostHistoricalMetrics AS PD_AA ON Q.AcceptedAnswerId = PD_AA.PostId AND Q.PostTypeId = 1
    WHERE Q.PostTypeId = 1
)
SELECT
    QDM.QuestionId,
    QDM.QuestionTitle,
    QDM.PrimaryTag,
    QDM.QuestionCreationDate,
    QDM.QuestionScore,
    QDM.QuestionViewCount,
    QDM.QuestionAnswerCount,
    QDM.QuestionFavoriteCount,
    QDM.MentionsPerformance,
    QDM.DaysToAcceptance,
    QDM.ViewToAnswerRatio,
    QDM.HoursToFirstEdit,
    QDM.UniqueEditors,
    QDM.WasReopened,
    UES_Q.DisplayName AS QuestionOwnerDisplayName,
    UES_Q.Reputation AS QuestionOwnerReputation,
    UES_Q.TotalQuestionsAsked AS QuestionOwnerTotalQuestions,
    UES_Q.ReputationTier AS QuestionOwnerReputationTier,
    UES_A.DisplayName AS AcceptedAnswerOwnerDisplayName,
    UES_A.Reputation AS AcceptedAnswerOwnerReputation,
    UES_A.TotalAnswersGiven AS AcceptedAnswerOwnerTotalAnswers,
    QDM.AnswerScore AS TopAnswerScore,
    QDM.AnswerCreationDate AS TopAnswerCreationDate,
    -- Correlated subquery: Average score of all posts by the question owner
    (
        SELECT AVG(P_UO.Score)
        FROM Posts AS P_UO
        WHERE P_UO.OwnerUserId = QDM.QuestionOwnerUserId AND P_UO.Id != QDM.QuestionId
          AND P_UO.CreationDate < QDM.QuestionCreationDate -- Only posts before this question
          AND P_UO.Score IS NOT NULL
    ) AS AvgQuestionOwnerOtherPostScore,
    -- Correlated subquery: Does any comment on this question contain a link to an external resource?
    EXISTS (
        SELECT 1
        FROM Comments AS C_Link
        WHERE C_Link.PostId = QDM.QuestionId
          AND C_Link.Text ILIKE '%http://%' OR C_Link.Text ILIKE '%https://%'
    ) AS HasExternalLinkInComments,
    -- Calculate a "Hotness Score" using multiple factors and NULL-safe logic
    (
        COALESCE(QDM.QuestionScore, 0) * 1.5
        + COALESCE(QDM.QuestionFavoriteCount, 0) * 2.0
        + COALESCE(QDM.QuestionViewCount, 0) / 100.0
        + (CASE WHEN QDM.AcceptedAnswerPostId IS NOT NULL THEN 100 ELSE 0 END)
        - (CASE WHEN QDM.PostAgeMonths > 12 THEN (QDM.PostAgeMonths - 12) * 5 ELSE 0 END) -- Penalize old questions
        + (CASE WHEN QDM.MentionsPerformance THEN 50 ELSE 0 END)
        + (CASE WHEN QDM.WasReopened THEN 25 ELSE 0 END)
    ) AS HotnessScore,
    -- Window function: Calculate cumulative answer score percentage for a question's lifecycle
    SUM(QDM.AnswerScore) OVER (PARTITION BY QDM.QuestionId ORDER BY QDM.AnswerCreationDate) /
    NULLIF(SUM(QDM.AnswerScore) OVER (PARTITION BY QDM.QuestionId), 0) * 100 AS CumulativeAnswerScorePercent,
    -- String manipulation: Identify questions with specific technology stack tags
    CASE
        WHEN QDM.Tags ILIKE '%<javascript>%' AND QDM.Tags ILIKE '%<node.js>%' THEN 'JavaScript/Node.js Stack'
        WHEN QDM.Tags ILIKE '%<python>%' AND QDM.Tags ILIKE '%<django>%' THEN 'Python/Django Stack'
        WHEN QDM.Tags ILIKE '%<c#>%<asp.net-core>%' THEN 'C#/.NET Core Stack'
        WHEN QDM.Tags ILIKE '%<java>%' AND QDM.Tags ILIKE '%<spring>%' THEN 'Java/Spring Stack'
        ELSE 'Other/Mixed Stack'
    END AS TechStackCategory,
    -- Calculate how many days passed since a close vote was logged for this question
    (
        SELECT MAX(DATE_PART('day', NOW() - PHC.CreationDate))
        FROM PostHistory AS PHC
        WHERE PHC.PostId = QDM.QuestionId
        AND PHC.PostHistoryTypeId = 10 -- Post Closed
    ) AS DaysSinceLastClosedVote
FROM QuestionDerivedMetrics AS QDM
LEFT JOIN UserEngagementSummary AS UES_Q ON QDM.QuestionOwnerUserId = UES_Q.UserId
LEFT JOIN UserEngagementSummary AS UES_A ON QDM.AnswerOwnerUserId = UES_A.UserId
WHERE
    QDM.PostTypeId = 1
    AND QDM.AnswerScoreRank = 1 -- Only consider the top-ranked answer for each question
    AND QDM.QuestionViewCount > 10000 -- Focus on popular questions
    AND QDM.QuestionAnswerCount >= 3 -- At least three answers
    AND QDM.QuestionFavoriteCount > 50 -- Many users favorited it
    AND QDM.QuestionCreationDate BETWEEN NOW() - INTERVAL '5 year' AND NOW() - INTERVAL '6 month' -- Questions from the last 5 years, but not too recent
    AND (UES_Q.Reputation IS NULL OR UES_Q.Reputation > 1000) -- Owner has decent reputation or is deleted/community user
    AND QDM.WasReopened = FALSE -- Exclude reopened questions for this analysis
    -- Correlated subquery in WHERE: Question must have been edited by at least 2 different users
    AND (
        SELECT COUNT(DISTINCT PH_Edit.UserId)
        FROM PostHistory AS PH_Edit
        WHERE PH_Edit.PostId = QDM.QuestionId
          AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
          AND PH_Edit.UserId IS NOT NULL
    ) >= 2
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks AS PL_Dup
        WHERE PL_Dup.PostId = QDM.QuestionId
          AND PL_Dup.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
    ) -- Exclude questions marked as duplicates
    AND (QDM.PrimaryTag IS NULL OR QDM.PrimaryTag NOT ILIKE '%obsolete%') -- Exclude questions with 'obsolete' in primary tag


UNION ALL


-- Alternative path: Recently active questions with high comment engagement, potentially with less overall activity but good discussion
SELECT
    QDM_ALT.PostId AS QuestionId,
    QDM_ALT.Title AS QuestionTitle,
    QDM_ALT.PrimaryTag,
    QDM_ALT.PostCreationDate AS QuestionCreationDate,
    QDM_ALT.PostScore AS QuestionScore,
    QDM_ALT.ViewCount AS QuestionViewCount,
    QDM_ALT.AnswerCount AS QuestionAnswerCount,
    QDM_ALT.FavoriteCount AS QuestionFavoriteCount,
    QDM_ALT.MentionsPerformance,
    NULL AS DaysToAcceptance, -- Not applicable as we don't focus on accepted answers here
    COALESCE(CAST(QDM_ALT.AnswerCount AS NUMERIC) / NULLIF(QDM_ALT.ViewCount, 0) * 100, 0) AS ViewToAnswerRatio,
    QDM_ALT.HoursToFirstEdit,
    QDM_ALT.UniqueEditors,
    QDM_ALT.WasReopened,
    UES_Q_ALT.DisplayName AS QuestionOwnerDisplayName,
    UES_Q_ALT.Reputation AS QuestionOwnerReputation,
    UES_Q_ALT.TotalQuestionsAsked AS QuestionOwnerTotalQuestions,
    UES_Q_ALT.ReputationTier AS QuestionOwnerReputationTier,
    NULL AS AcceptedAnswerOwnerDisplayName,
    NULL AS AcceptedAnswerOwnerReputation,
    NULL AS AcceptedAnswerOwnerTotalAnswers,
    NULL AS TopAnswerScore,
    NULL AS TopAnswerCreationDate,
    (
        SELECT AVG(P_UO_ALT.Score)
        FROM Posts AS P_UO_ALT
        WHERE P_UO_ALT.OwnerUserId = QDM_ALT.OwnerUserId AND P_UO_ALT.Id != QDM_ALT.PostId
          AND P_UO_ALT.CreationDate < QDM_ALT.PostCreationDate
          AND P_UO_ALT.Score IS NOT NULL
    ) AS AvgQuestionOwnerOtherPostScore,
    EXISTS (
        SELECT 1
        FROM Comments AS C_Link_ALT
        WHERE C_Link_ALT.PostId = QDM_ALT.PostId
          AND C_Link_ALT.Text ILIKE '%http://%' OR C_Link_ALT.Text ILIKE '%https://%'
    ) AS HasExternalLinkInComments,
    (
        COALESCE(QDM_ALT.PostScore, 0) * 1.0
        + COALESCE(QDM_ALT.PostCommentCount, 0) * 5.0 -- High weight for comments
        + COALESCE(QDM_ALT.ViewCount, 0) / 500.0
        + (CASE WHEN QDM_ALT.MentionsPerformance THEN 20 ELSE 0 END)
        + (CASE WHEN QDM_ALT.PostAgeMonths < 6 THEN 30 ELSE 0 END) -- Favor newer questions
    ) AS HotnessScore,
    NULL AS CumulativeAnswerScorePercent, -- Not relevant for this path
    CASE
        WHEN QDM_ALT.Tags ILIKE '%<security>%' OR QDM_ALT.Tags ILIKE '%<privacy>%' THEN 'Security/Privacy Topic'
        WHEN QDM_ALT.Tags ILIKE '%<data-science>%' OR QDM_ALT.Tags ILIKE '%<machine-learning>%' THEN 'Data Science/ML Topic'
        ELSE 'General Discussion Topic'
    END AS TechStackCategory,
    (
        SELECT MAX(DATE_PART('day', NOW() - PHC_ALT.CreationDate))
        FROM PostHistory AS PHC_ALT
        WHERE PHC_ALT.PostId = QDM_ALT.PostId
        AND PHC_ALT.PostHistoryTypeId = 10
    ) AS DaysSinceLastClosedVote
FROM PostHistoricalMetrics AS QDM_ALT
LEFT JOIN UserEngagementSummary AS UES_Q_ALT ON QDM_ALT.OwnerUserId = UES_Q_ALT.UserId
WHERE
    QDM_ALT.PostTypeId = 1
    AND QDM_ALT.PostCommentCount >= 20 -- Questions with very active comments
    AND QDM_ALT.ViewCount BETWEEN 1000 AND 10000 -- Medium popular
    AND QDM_ALT.PostAgeMonths <= 12 -- Relatively new questions (last year)
    AND QDM_ALT.ClosedDate IS NULL -- Not closed
    AND QDM_ALT.AcceptedAnswerId IS NULL -- No accepted answer (frequently controversial or discussion-oriented)
    AND EXISTS (
        SELECT 1
        FROM Comments AS C_Recent
        WHERE C_Recent.PostId = QDM_ALT.PostId
          AND C_Recent.CreationDate > NOW() - INTERVAL '1 month'
    ) -- At least one comment in the last month
ORDER BY HotnessScore DESC, QuestionCreationDate DESC
LIMIT 1000;
