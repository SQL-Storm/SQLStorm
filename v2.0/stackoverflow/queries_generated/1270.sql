-- {"query": "1270.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3804} 

WITH UserEngagementSummary AS (
    -- Summarizes user-level activity, vote history, and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.UserId IS NOT NULL) AS TotalVotesCast, -- Votes where user is the voter
        SUM(CASE WHEN VT.Name = 'UpMod' AND V.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalUpVotesCast,
        SUM(CASE WHEN VT.Name = 'DownMod' AND V.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalDownVotesCast,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(U.LastAccessDate, U.CreationDate) AS UserLastAccessDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    LEFT JOIN VoteTypes AS VT ON V.VoteTypeId = VT.Id
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoryAndStatus AS (
    -- Gathers post-level edit history and close/reopen/delete status details
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDate,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened'
                 WHEN PH.PostHistoryTypeId = 12 THEN 'Deleted'
                 WHEN PH.PostHistoryTypeId = 13 THEN 'Undeleted'
                 WHEN PH.PostHistoryTypeId = 35 THEN 'Migrated Away'
                 WHEN PH.PostHistoryTypeId = 36 THEN 'Migrated Here'
                 ELSE NULL END) AS LatestStatusChangeType,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 10) AS ClosedEventDate,
        -- Extract CloseReasonTypeId from Comment field if PostHistoryTypeId is 10
        COALESCE(CAST(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS SMALLINT), -1) AS CloseReasonTypeId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10) AS CloseVoteCount,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS ReopenVoteCount
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
QuestionAnswerEngagement AS (
    -- Aggregates metrics for questions and their answers, including time to first answer
    SELECT
        Q.Id AS QuestionId,
        Q.CreationDate AS QuestionCreationDate,
        Q.AcceptedAnswerId,
        COUNT(A.Id) AS TotalAnswersReceived,
        MIN(A.CreationDate) AS FirstAnswerDate,
        AVG(A.Score) FILTER (WHERE A.Score IS NOT NULL) AS AvgAnswerScore,
        SUM(CASE WHEN V_Q.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotes,
        SUM(CASE WHEN V_Q.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotes,
        MAX(Q.FavoriteCount) AS QuestionFavoriteCount,
        MAX(Q.ViewCount) AS QuestionViewCount,
        BOOL_OR(Q.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer
    FROM Posts AS Q
    LEFT JOIN Posts AS A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    LEFT JOIN Votes AS V_Q ON Q.Id = V_Q.PostId AND V_Q.VoteTypeId IN (2, 3, 5)
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.CreationDate, Q.AcceptedAnswerId
),
TagPerformanceMetrics AS (
    -- Parses tags from questions and links them to associated badges and scores
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        P.Id AS PostId,
        P.Score AS PostScore,
        P.CreationDate AS PostCreationDate,
        P.ViewCount AS PostViewCount
    FROM Posts AS P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
AggregatedTagMetrics AS (
    -- Further aggregates tag performance, including link to tag wiki posts and badge counts
    SELECT
        TPM.TagName,
        COUNT(DISTINCT TPM.PostId) AS QuestionsUsingTag,
        AVG(TPM.PostScore) AS AvgQuestionScoreForTag,
        AVG(TPM.PostViewCount) AS AvgQuestionViewCountForTag,
        MAX(T.WikiPostId) AS TagWikiPostId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesForTag,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesForTag,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesForTag
    FROM TagPerformanceMetrics AS TPM
    LEFT JOIN Tags AS T ON TPM.TagName = T.TagName
    LEFT JOIN Badges AS B ON T.TagName = B.Name AND B.TagBased IS TRUE -- Link tag to tag-based badges
    GROUP BY TPM.TagName
),
MostImpactfulQuestions AS (
    -- Identifies the most impactful question for each user based on a composite score
    SELECT
        Q.OwnerUserId,
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.CommentCount AS QuestionCommentCount,
        QAE.TotalAnswersReceived,
        QAE.AvgAnswerScore,
        (Q.Score * 1.5 + Q.ViewCount / 100.0 + QAE.TotalAnswersReceived * 5 + COALESCE(QAE.QuestionFavoriteCount, 0) * 10 + COALESCE(Q.CommentCount, 0) * 2) AS ImpactScore,
        ROW_NUMBER() OVER (PARTITION BY Q.OwnerUserId ORDER BY (Q.Score * 1.5 + Q.ViewCount / 100.0 + QAE.TotalAnswersReceived * 5 + COALESCE(QAE.QuestionFavoriteCount, 0) * 10 + COALESCE(Q.CommentCount, 0) * 2) DESC, Q.CreationDate DESC) AS rn
    FROM Posts AS Q
    JOIN QuestionAnswerEngagement AS QAE ON Q.Id = QAE.QuestionId
    WHERE Q.PostTypeId = 1 AND Q.OwnerUserId IS NOT NULL
),
MostImpactfulAnswers AS (
    -- Identifies the most impactful answer for each user based on its score and acceptance
    SELECT
        A.OwnerUserId,
        A.Id AS AnswerId,
        A.ParentId AS ParentQuestionId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        Q.AcceptedAnswerId AS ParentAcceptedAnswerId,
        (CASE WHEN Q.AcceptedAnswerId = A.Id THEN 100 ELSE 0 END + A.Score * 2 + COALESCE(A.CommentCount,0) * 1.5) AS AnswerImpactScore,
        ROW_NUMBER() OVER (PARTITION BY A.OwnerUserId ORDER BY (CASE WHEN Q.AcceptedAnswerId = A.Id THEN 100 ELSE 0 END + A.Score * 2 + COALESCE(A.CommentCount,0) * 1.5) DESC, A.CreationDate DESC) AS rn
    FROM Posts AS A
    JOIN Posts AS Q ON A.ParentId = Q.Id
    WHERE A.PostTypeId = 2 AND A.OwnerUserId IS NOT NULL
)
-- Main query to combine all insights, focusing on high-impact users and their best contributions
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalPosts,
    UES.TotalQuestions,
    UES.TotalAnswers,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    UES.UserLastAccessDate,
    AGE(CURRENT_TIMESTAMP, UES.UserCreationDate) AS UserAccountAge, -- Date arithmetic to get account age
    MIQ.QuestionId AS MostImpactfulQuestionId,
    MIQ.QuestionTitle AS MostImpactfulQuestionTitle,
    MIQ.QuestionScore AS MIQ_Score,
    MIQ.QuestionViewCount AS MIQ_ViewCount,
    MIQ.TotalAnswersReceived AS MIQ_TotalAnswers,
    MIQ.AvgAnswerScore AS MIQ_AvgAnswerScore,
    PEH_Q.TotalEdits AS MIQ_TotalEdits,
    PEH_Q.LatestStatusChangeType AS MIQ_LatestStatus,
    CR.Name AS MIQ_CloseReason, -- Outer join to CloseReasonTypes via PostHistoryAndStatus
    (MIQ.QuestionUpVotes - MIQ.QuestionDownVotes) AS MIQ_NetVotes,
    (EXTRACT(EPOCH FROM (MIQ.FirstAnswerDate - MIQ.QuestionCreationDate)) / 3600.0) AS MIQ_TimeToFirstAnswerHours, -- Time difference calculation
    MIA.AnswerId AS MostImpactfulAnswerId,
    MIA.AnswerScore AS MIA_Score,
    PEH_A.TotalEdits AS MIA_TotalEdits,
    MIA.ParentQuestionId AS MIA_ParentQuestionId,
    -- Correlated subquery: check if user has commented on their own impactful question with a long comment
    EXISTS (
        SELECT 1
        FROM Comments AS C_MIQ
        WHERE C_MIQ.PostId = MIQ.QuestionId
          AND C_MIQ.UserId = UES.UserId
          AND LENGTH(C_MIQ.Text) > 75 -- String expression: check comment length
          AND C_MIQ.CreationDate > MIQ.QuestionCreationDate - INTERVAL '1 day' -- Time based predicate
    ) AS HasUserSelfCommentedOnMIQ_Long,
    -- Window function: Rank users by reputation within activity tiers (e.g., total questions posted)
    RANK() OVER (ORDER BY UES.Reputation DESC, UES.TotalPosts DESC) AS UserOverallRank,
    NTILE(10) OVER (ORDER BY UES.Reputation DESC) AS ReputationDecile, -- NTILE for bucketing users into percentiles
    -- Tags related to the most impactful question, aggregated with their usage count
    (
        SELECT STRING_AGG(DISTINCT atm.TagName || ' (Q:' || atm.QuestionsUsingTag || ', G:' || atm.GoldBadgesForTag || ')', '; ')
        FROM TagPerformanceMetrics tpm_sub
        JOIN AggregatedTagMetrics atm ON tpm_sub.TagName = atm.TagName
        WHERE tpm_sub.PostId = MIQ.QuestionId
    ) AS MIQ_RelatedTagsWithStats,
    -- More complex calculation / NULL handling: Views per accepted answer for the impactful question
    COALESCE(MIQ.QuestionViewCount / NULLIF(CASE WHEN MIQ.HasAcceptedAnswer THEN MIQ.TotalAnswersReceived ELSE 0 END, 0), 0.0) AS MIQ_ViewsPerAcceptedAnswer,
    -- Another correlated subquery: check for linked duplicate posts for the impactful question
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE (PL.PostId = MIQ.QuestionId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate'))
           OR (PL.RelatedPostId = MIQ.QuestionId AND PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate'))
    ) AS MIQ_HasDuplicateLink,
    -- String expression and NULL logic for question title: first 10 chars, upper case, or 'N/A'
    UPPER(LEFT(COALESCE(MIQ.QuestionTitle, 'N/A'), 10)) AS TitlePrefixUpper,
    -- Conditional expression based on various user and post performance factors
    CASE
        WHEN UES.Reputation > 10000 AND UES.GoldBadges >= 3 AND MIQ.TotalAnswersReceived > 10 AND MIQ.AvgAnswerScore > 5 THEN 'Highly Influential Expert'
        WHEN UES.Reputation > 5000 AND MIQ.ImpactScore > 500 AND MIA.AnswerImpactScore IS NOT NULL AND MIA.AnswerScore > 50 THEN 'Proactive Contributor & Problem Solver'
        WHEN UES.TotalAnswers > UES.TotalQuestions * 3 AND UES.TotalAnswers > 50 THEN 'Dedicated Answerer'
        WHEN UES.TotalQuestions > UES.TotalAnswers * 3 AND UES.TotalQuestions > 20 THEN 'Prolific Questioner'
        WHEN UES.TotalComments > 100 AND UES.TotalPosts > 50 THEN 'Engaged Community Member'
        ELSE 'General Participant'
    END AS UserProfileCategory,
    -- Average score of questions owned by the user
    AVG(Q_User.Score) OVER (PARTITION BY UES.UserId) AS UserAvgQuestionScore,
    -- Average reputation of users who answered this user's most impactful question
    (
        SELECT AVG(AU.Reputation)
        FROM Posts A_Sub
        JOIN Users AU ON A_Sub.OwnerUserId = AU.Id
        WHERE A_Sub.ParentId = MIQ.QuestionId AND A_Sub.PostTypeId = 2
    ) AS AvgAnswererReputationOnMIQ,
    -- Check if the user is a "reopener" (has reopened more than 3 posts)
    (SELECT COUNT(*) FROM PostHistory ph_r WHERE ph_r.UserId = UES.UserId AND ph_r.PostHistoryTypeId = 11) > 3 AS IsFrequentReopener
FROM UserEngagementSummary AS UES
LEFT JOIN MostImpactfulQuestions AS MIQ ON UES.UserId = MIQ.OwnerUserId AND MIQ.rn = 1
LEFT JOIN PostHistoryAndStatus AS PEH_Q ON MIQ.QuestionId = PEH_Q.PostId
LEFT JOIN CloseReasonTypes AS CR ON PEH_Q.CloseReasonTypeId = CR.Id
LEFT JOIN MostImpactfulAnswers AS MIA ON UES.UserId = MIA.OwnerUserId AND MIA.rn = 1
LEFT JOIN PostHistoryAndStatus AS PEH_A ON MIA.AnswerId = PEH_A.PostId
LEFT JOIN Posts AS Q_User ON UES.UserId = Q_User.OwnerUserId AND Q_User.PostTypeId = 1 -- Used for UserAvgQuestionScore window function
-- Set operator example: Filter for users who have both asked and answered posts
WHERE UES.UserId IN (
    SELECT UQ.OwnerUserId FROM Posts UQ WHERE UQ.PostTypeId = 1 AND UQ.OwnerUserId IS NOT NULL
    INTERSECT
    SELECT UA.OwnerUserId FROM Posts UA WHERE UA.PostTypeId = 2 AND UA.OwnerUserId IS NOT NULL
)
ORDER BY UES.Reputation DESC, MIQ.ImpactScore DESC NULLS LAST
LIMIT 100;
