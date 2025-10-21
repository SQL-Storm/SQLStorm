-- {"query": "19086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2999} 
WITH UserEngagement AS (
    -- Summarize user activity and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.CreationDate >= '2015-01-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 AND SUM(COALESCE(P.Score, 0)) > -10
),
ClassifiedUsers AS (
    -- Classify users into groups based on reputation and activity, using a set operator
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.CreationDate,
        UE.UserProfileViews,
        UE.UserUpVotesGiven,
        UE.UserDownVotesGiven,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.TotalPostScore,
        UE.TotalCommentScore,
        UE.AvgQuestionViewCount,
        UE.LastPostActivityDate,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        'HighReputationContributor' AS UserGroup
    FROM UserEngagement UE
    WHERE UE.Reputation >= 15000 AND UE.TotalQuestions >= 15 AND UE.GoldBadges >= 1
    UNION ALL
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.CreationDate,
        UE.UserProfileViews,
        UE.UserUpVotesGiven,
        UE.UserDownVotesGiven,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.TotalPostScore,
        UE.TotalCommentScore,
        UE.AvgQuestionViewCount,
        UE.LastPostActivityDate,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        'ModerateActiveUser' AS UserGroup
    FROM UserEngagement UE
    WHERE UE.Reputation BETWEEN 1000 AND 14999
      AND UE.TotalPosts BETWEEN 5 AND 100
      AND UE.TotalComments > 10
      AND UE.GoldBadges = 0
),
PostTagStats AS (
    -- Extract tags and basic question stats, including a correlated subquery for linked posts
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS QuestionOwnerId,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.AnswerCount,
        P.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        (
            SELECT COUNT(DISTINCT L.RelatedPostId)
            FROM PostLinks L
            WHERE L.PostId = P.Id AND L.LinkTypeId = 1
        ) AS LinkedPostsCount
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.Tags IS NOT NULL
      AND P.CreationDate BETWEEN '2016-01-01' AND '2020-12-31'
),
PostHistoryDetails AS (
    -- Track relevant post history (edits, closes) and calculate time differences using a window function
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        -- Use LAG to find the previous edit date for the same post, partitioned by history type for specific edits
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate) AS PreviousEditDate,
        CASE
            WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND PH.Comment ~ '^[0-9]+$' THEN CAST(PH.Comment AS SMALLINT) -- Old close reasons
            WHEN PH.PostHistoryTypeId IN (101, 102, 103, 104, 105) THEN PH.PostHistoryTypeId -- Modern close reasons
            ELSE NULL
        END AS CloseReasonTypeId,
        -- Get the most recent relevant history entry for each post
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 10, 101, 102, 103, 104, 105) -- Body/Title edits, and Close events
),
LatestPostEditInfo AS (
    -- Filter PostHistoryDetails to only the latest edit/close information and join with CloseReasonTypes
    SELECT
        PHD.PostId,
        PHD.EditorUserId,
        PHD.EditDate,
        PHD.PreviousEditDate,
        PHD.CloseReasonTypeId,
        CRT.Name AS CloseReasonName,
        EXTRACT(EPOCH FROM (PHD.EditDate - PHD.PreviousEditDate)) / 3600 AS TimeSinceLastEditHours -- Time difference in hours
    FROM PostHistoryDetails PHD
    LEFT JOIN CloseReasonTypes CRT ON PHD.CloseReasonTypeId = CRT.Id
    WHERE PHD.rn = 1
),
AnswerQuality AS (
    -- Analyze answer quality and rank them per question using a window function
    SELECT
        P.ParentId AS QuestionId,
        P.Id AS AnswerId,
        P.OwnerUserId AS AnswererUserId,
        P.Score AS AnswerScore,
        LENGTH(P.Body) AS AnswerBodyLength,
        ROW_NUMBER() OVER (PARTITION BY P.ParentId ORDER BY P.Score DESC, P.CreationDate ASC) AS rn_top_answer
    FROM Posts P
    WHERE P.PostTypeId = 2 -- Only answers
)
SELECT
    CU.UserId,
    CU.DisplayName,
    CU.Reputation,
    CU.UserGroup,
    CU.TotalQuestions,
    CU.TotalAnswers,
    CU.AvgQuestionViewCount,
    CU.GoldBadges,
    CU.SilverBadges,
    CU.BronzeBadges,
    PQS.PostId AS QuestionId,
    PQS.QuestionScore,
    PQS.QuestionViewCount,
    PQS.AnswerCount,
    PQS.AcceptedAnswerId,
    COALESCE(LPEI.CloseReasonName, 'N/A') AS LatestCloseReason, -- NULL logic COALESCE
    COALESCE(LPEI.TimeSinceLastEditHours, 0.0) AS HoursSinceLatestEdit,
    ARRAY_TO_STRING(PQS.TagArray, '; ') AS TagsList, -- String array to string
    PQS.LinkedPostsCount,
    AQ.AnswererUserId AS TopAnswererId,
    AQ.AnswerScore AS TopAnswerScore,
    AQ.AnswerBodyLength AS TopAnswerBodyLength,
    -- Correlated subquery: count user's comments on their own question within 24 hours of question creation
    (
        SELECT COUNT(DISTINCT C_sub.Id)
        FROM Comments C_sub
        WHERE C_sub.PostId = PQS.PostId
          AND C_sub.UserId = CU.UserId
          AND C_sub.CreationDate > PQS.QuestionCreationDate
          AND C_sub.CreationDate <= PQS.QuestionCreationDate + INTERVAL '24 hours'
    ) AS UserCommentsOnOwnQuestionImmediate,
    -- Complex CASE expression for detailed user tier classification
    CASE
        WHEN CU.GoldBadges >= 2 AND CU.Reputation > 100000 THEN 'Legendary Contributor'
        WHEN CU.SilverBadges >= 5 AND CU.TotalQuestions >= 50 AND CU.TotalPostScore >= 1000 THEN 'High Impact Author'
        WHEN CU.UserGroup = 'HighReputationContributor' AND CU.TotalComments > 200 THEN 'Community Influencer'
        WHEN CU.UserGroup = 'ModerateActiveUser' AND CU.TotalPosts > 20 THEN 'Dedicated Participant'
        ELSE 'General Engager'
    END AS DetailedUserTier,
    ABS(CU.UserUpVotesGiven - CU.UserDownVotesGiven) AS VoteBalanceAbsolute, -- Absolute calculation
    -- Correlated subquery: aggregate moderator-only tags for the question
    (
        SELECT STRING_AGG(DISTINCT T.TagName, ' | ')
        FROM UNNEST(PQS.TagArray) AS T_alias(TagName) -- UNNEST for array iteration
        JOIN Tags T ON T.TagName = T_alias.TagName
        WHERE T.IsModeratorOnly = TRUE
    ) AS ModeratorOnlyQuestionTags,
    P_Accepted.ContentLicense AS AcceptedAnswerLicense,
    NULLIF(TRIM(SUBSTRING(P_Accepted.Body, 1, 150)), '') AS AcceptedAnswerBodyExcerpt, -- String manipulation, NULLIF
    -- Window function: Rank users within their classified group by reputation
    RANK() OVER (PARTITION BY CU.UserGroup ORDER BY CU.Reputation DESC, CU.TotalPosts DESC) AS UserGroupReputationRank,
    -- Window function: Get the score of the previous question posted by the same user
    LAG(PQS.QuestionScore, 1, 0) OVER (PARTITION BY CU.UserId ORDER BY PQS.QuestionCreationDate ASC) AS PreviousQuestionScore,
    -- Complex conditional logic for question acceptance status
    CASE
        WHEN P_Accepted.Id IS NOT NULL AND P_Accepted.Score > 0 THEN 'Accepted (Positive Score)'
        WHEN PQS.AcceptedAnswerId IS NOT NULL AND (P_Accepted.Id IS NULL OR P_Accepted.Score <= 0) THEN 'Accepted (Zero/Negative Score)'
        WHEN PQS.AcceptedAnswerId IS NULL AND PQS.AnswerCount > 0 THEN 'Has Answers, Not Accepted'
        ELSE 'No Answers or Accepted Answer'
    END AS QuestionAcceptanceStatusDetailed
FROM ClassifiedUsers CU
JOIN PostTagStats PQS ON CU.UserId = PQS.QuestionOwnerId
LEFT JOIN LatestPostEditInfo LPEI ON PQS.PostId = LPEI.PostId
LEFT JOIN AnswerQuality AQ ON PQS.PostId = AQ.QuestionId AND AQ.rn_top_answer = 1 -- Join for the single top-scoring answer
LEFT JOIN Posts P_Accepted ON PQS.AcceptedAnswerId = P_Accepted.Id AND P_Accepted.PostTypeId = 2 -- Details of the accepted answer
WHERE PQS.QuestionScore >= -5 -- Filtering on calculated score
  AND (CU.DisplayName IS NOT NULL AND LENGTH(CU.DisplayName) > 4 AND CU.DisplayName ILIKE 's%_dev%' OR CU.DisplayName IS NULL AND CU.Reputation > 5000) -- String expressions and NULL logic
  AND (PQS.TagArray @> ARRAY['sql'] OR PQS.TagArray @> ARRAY['performance'] OR PQS.TagArray @> ARRAY['database']) -- Array containment check
  AND CU.LastPostActivityDate IS NOT NULL AND CU.LastPostActivityDate > CU.CreationDate + INTERVAL '2 years' -- Date calculations
  AND PQS.QuestionViewCount > 500
ORDER BY DetailedUserTier DESC, UserGroupReputationRank ASC, PQS.QuestionScore DESC, HoursSinceLatestEdit ASC
LIMIT 1000;