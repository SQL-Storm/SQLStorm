-- {"query": "1148.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3017} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersProvided,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        -- Calculate an "Engagement Score" incorporating reputation, views, votes, and post count, handling NULLs
        COALESCE(U.Reputation * 0.1, 0) + COALESCE(U.Views * 0.005, 0) + COALESCE(U.UpVotes * 0.2, 0) - COALESCE(U.DownVotes * 0.1, 0) + (COUNT(DISTINCT P.Id) * 1) AS EngagementScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
QuestionMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.CreationDate AS QuestionCreationDate,
        P.LastActivityDate AS QuestionLastActivityDate,
        P.LastEditDate AS QuestionLastEditDate,
        P.ClosedDate AS QuestionClosedDate,
        P.AcceptedAnswerId,
        -- Extract and clean the primary tag from the Tags string, handling potential NULLs or empty strings
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND POSITION('>' IN P.Tags) > 1
            THEN LOWER(SUBSTRING(P.Tags, 2, POSITION('>' IN P.Tags) - 2))
            ELSE 'no-tag'
        END AS PrimaryTag,
        -- Calculate a complex 'Question Impact Score' based on various metrics
        (P.Score * 0.6) + (COALESCE(P.ViewCount, 0) * 0.005) + (COALESCE(P.AnswerCount, 0) * 1.5) + (COALESCE(P.FavoriteCount, 0) * 2) AS QuestionImpactScore
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Only questions
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.UserId) AS DistinctEditorsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS TotalEditEvents, -- Count of title/body/tag edits
        -- Correlated subquery to find the last user who edited a post, excluding the owner
        (SELECT PH2.UserId
         FROM PostHistory PH2
         WHERE PH2.PostId = PH.PostId
           AND PH2.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
           AND PH2.UserId IS NOT NULL
           AND PH2.UserId != (SELECT P.OwnerUserId FROM Posts P WHERE P.Id = PH.PostId) -- Ensure not the post owner
         ORDER BY PH2.CreationDate DESC
         LIMIT 1) AS LastNonOwnerEditorId,
        -- Correlated subquery to find the name of the very first close reason for a post
        (SELECT CRT.Name
         FROM PostHistory PH3
         JOIN CloseReasonTypes CRT ON CAST(PH3.Comment AS SMALLINT) = CRT.Id -- Assuming Comment is numeric for close reasons
         WHERE PH3.PostId = PH.PostId
           AND PH3.PostHistoryTypeId = 10 -- Post Closed event
         ORDER BY PH3.CreationDate ASC
         LIMIT 1) AS FirstCloseReasonName,
        -- Count unique users who participated in a close vote
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 AND PH.UserId IS NOT NULL THEN PH.UserId END) AS CloseVoteUserCount
    FROM PostHistory PH
    GROUP BY PH.PostId
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeAwardDate,
        -- Correlated subquery to get the name of the most recently awarded badge
        (SELECT B2.Name FROM Badges B2 WHERE B2.UserId = B.UserId ORDER BY B2.Date DESC LIMIT 1) AS LatestBadgeName,
        -- Rank users based on their gold and silver badge counts, then by latest badge date
        RANK() OVER (ORDER BY COUNT(CASE WHEN B.Class = 1 THEN B.Id END) DESC, COUNT(CASE WHEN B.Class = 2 THEN B.Id END) DESC, MAX(B.Date) DESC) AS UserOverallBadgeRank
    FROM Badges B
    GROUP BY B.UserId
),
CommentSentiment AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        MAX(C.CreationDate) AS LastCommentDate,
        -- Count comments containing positive sentiment keywords (case-insensitive)
        SUM(CASE WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        -- Count comments containing negative sentiment keywords
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        -- Correlated subquery to retrieve the text of the most recent comment for the post
        (SELECT C2.Text FROM Comments C2 WHERE C2.PostId = C.PostId ORDER BY C2.CreationDate DESC LIMIT 1) AS MostRecentCommentText
    FROM Comments C
    GROUP BY C.PostId
),
-- Use a set operator (UNION ALL) to define "High Impact User Candidates" based on two different criteria
HighImpactUserCandidates AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        'Gold Badge & Accepted Answer Contributor' AS Criteria
    FROM UserEngagement UE
    JOIN UserBadgeStats UBS ON UE.UserId = UBS.UserId
    JOIN Posts P_ACC ON UE.UserId = P_ACC.OwnerUserId AND P_ACC.AcceptedAnswerId IS NOT NULL AND P_ACC.PostTypeId = 2 -- An owner has an accepted *answer*
    WHERE UBS.GoldBadges > 0

    UNION ALL

    SELECT
        UE.UserId,
        UE.DisplayName,
        'High Volume Questions & Avg Score' AS Criteria
    FROM UserEngagement UE
    WHERE UE.QuestionsAsked > 10 AND UE.AvgQuestionScore > 5
),
TagPopularity AS (
    SELECT
        QM.PrimaryTag,
        COUNT(QM.PostId) AS TaggedQuestionCount,
        SUM(QM.ViewCount) AS TotalTagViewCount,
        AVG(QM.QuestionImpactScore) AS AvgTagImpactScore,
        -- Rank tags by total view count, then by question count
        RANK() OVER (ORDER BY SUM(QM.ViewCount) DESC, COUNT(QM.PostId) DESC) AS TagViewRank
    FROM QuestionMetrics QM
    WHERE QM.PrimaryTag IS NOT NULL AND QM.PrimaryTag != 'no-tag'
    GROUP BY QM.PrimaryTag
)
-- Main Query: Combine all CTEs and add more complex logic, window functions, and filtering
SELECT
    U.Id AS UserID,
    U.DisplayName,
    UE.Reputation,
    UE.EngagementScore,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.LatestBadgeName,
    UBS.UserOverallBadgeRank,
    UE.QuestionsAsked,
    UE.AnswersProvided,
    UE.AvgQuestionScore,
    UE.AvgAnswerScore,
    QM.Title AS TopQuestionTitle,
    QM.QuestionImpactScore AS TopQuestionImpact,
    QM.ViewCount AS TopQuestionViews,
    QM.AnswerCount AS TopQuestionAnswers,
    PHA.DistinctEditorsCount AS TopQuestionDistinctEditors,
    PHA.TotalEditEvents AS TopQuestionEditEvents,
    PHA.FirstCloseReasonName AS TopQuestionCloseReason,
    CS.MostRecentCommentText AS TopQuestionLatestComment,
    CS.PositiveCommentCount AS TopQuestionPositiveComments,
    CS.NegativeCommentCount AS TopQuestionNegativeComments,
    TP.AvgTagImpactScore AS PrimaryTagAvgImpact,
    TP.TagViewRank AS PrimaryTagGlobalRank,
    (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = PHA.LastNonOwnerEditorId) AS LastNonOwnerEditorDisplayName, -- Fetch editor's DisplayName
    COALESCE(U.Location, 'Unknown Location') AS UserLocation, -- Handle NULL location
    -- Calculate days since last post activity using date arithmetic
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - UE.LastPostActivityDate)) / (3600 * 24) AS DaysSinceLastPostActivity,
    -- Calculate upvote to downvote ratio, handling potential division by zero
    CAST(UE.TotalUpVotesGiven AS DECIMAL) / NULLIF(UE.TotalDownVotesGiven, 0) AS UpVoteDownVoteRatio,
    -- Window function: Calculate average reputation of users within the same geographic location
    AVG(UE.Reputation) OVER (PARTITION BY COALESCE(U.Location, 'UNKNOWN')) AS AvgReputationInLocation,
    -- Window function: Rank questions by impact score within their primary tag category
    ROW_NUMBER() OVER (PARTITION BY QM.PrimaryTag ORDER BY QM.QuestionImpactScore DESC, QM.ViewCount DESC) AS RankWithinPrimaryTag,
    -- Boolean flag indicating if the user meets any "high impact" criteria from the UNION ALL CTE
    CASE WHEN HIC.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS IsHighImpactCandidate,
    HIC.Criteria AS HighImpactCriteriaMet
FROM Users U
JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
LEFT JOIN HighImpactUserCandidates HIC ON U.Id = HIC.UserId
-- Lateral join to efficiently find the single highest impact question for each user
LEFT JOIN LATERAL (
    SELECT *
    FROM QuestionMetrics qm_lat
    WHERE qm_lat.OwnerUserId = U.Id
    ORDER BY qm_lat.QuestionImpactScore DESC, qm_lat.QuestionCreationDate DESC
    LIMIT 1
) QM ON TRUE
LEFT JOIN PostHistoryAnalysis PHA ON QM.PostId = PHA.PostId
LEFT JOIN CommentSentiment CS ON QM.PostId = CS.PostId
LEFT JOIN TagPopularity TP ON QM.PrimaryTag = TP.PrimaryTag
WHERE
    UE.Reputation > 1000 -- Filter for users with significant reputation
    AND (UBS.GoldBadges > 0 OR UBS.SilverBadges >= 2) -- Users with at least one gold or two or more silver badges
    AND UE.QuestionsAsked > 0 -- Ensure the user has asked at least one question
    AND QM.QuestionImpactScore IS NOT NULL AND QM.QuestionImpactScore > 10 -- Ensure their top question has a substantial impact score
    AND (U.CreationDate BETWEEN '2010-01-01' AND '2020-12-31') -- Filter users created within a specific decade
    -- Complex predicate with string matching, NULL handling, and logical operators
    AND (U.Location LIKE '%USA%' OR U.Location IS NULL OR U.Location LIKE '%Europe%' OR U.Location LIKE '%Canada%')
    AND NOT EXISTS ( -- Correlated subquery: Exclude users who have heavily downvoted and closed questions
        SELECT 1
        FROM Posts P_Problematic
        WHERE P_Problematic.OwnerUserId = U.Id
          AND P_Problematic.PostTypeId = 1
          AND P_Problematic.ClosedDate IS NOT NULL
          AND P_Problematic.Score < -5 -- Questions with very low scores and closed
    )
ORDER BY UE.EngagementScore DESC, UBS.UserOverallBadgeRank ASC, QM.QuestionImpactScore DESC
LIMIT 100;