-- {"query": "1699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3961} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UpVotesGiven, -- UpMod or Favorite (now saves)
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(P.Score) AS TotalPostScore,
        NULLIF(AVG(CAST(P.Score AS numeric)), 0) AS AveragePostScore, -- Avoid division by zero
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS TotalEditsMade,
        MAX(P.CreationDate) AS LatestPostDate,
        COALESCE((SELECT COUNT(DISTINCT T.TagName) FROM Tags T WHERE T.TagName IN (SELECT unnest(string_to_array(substring(P_sub.Tags, 2, length(P_sub.Tags)-2), '><')) FROM Posts P_sub WHERE P_sub.OwnerUserId = U.Id AND P_sub.Tags IS NOT NULL AND P_sub.PostTypeId = 1)), 0) AS UniqueTagsPostedAsQuestionOwner,
        SUM(U.Views) AS TotalProfileViews
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views
),
PostQualityMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS ActualAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.OwnerUserId AS QuestionOwnerId,
        U_Q.DisplayName AS QuestionOwnerDisplayName,
        COALESCE(Q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        A.Id AS AnswerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        A.OwnerUserId AS AnswerOwnerId,
        U_A.DisplayName AS AnswerOwnerDisplayName,
        (SELECT COUNT(Id) FROM Comments WHERE PostId = Q.Id) AS QuestionCommentCount,
        (SELECT COUNT(Id) FROM Comments WHERE PostId = A.Id) AS AnswerCommentCount,
        Q.Tags,
        (CASE WHEN Q.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END) AS HasAcceptedAnswer,
        (Q.CommunityOwnedDate IS NOT NULL) AS IsCommunityWiki,
        NULLIF(AVG(CASE WHEN V.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY Q.Id), 0) AS AvgUpVoteRatio,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId IN (2,3)) OVER (PARTITION BY Q.Id) AS TotalQuestionVotes,
        LAG(Q.LastEditDate, 1, Q.CreationDate) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PreviousPostEditDate,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS QuestionEditCount,
        (SELECT
            CASE
                WHEN PH_Close.Comment IS NOT NULL AND LENGTH(TRIM(PH_Close.Comment)) > 0 THEN
                    COALESCE(CR.Name, 'Unknown (' || PH_Close.Comment || ')')
                ELSE NULL
            END
         FROM PostHistory PH_Close
         LEFT JOIN CloseReasonTypes CR ON
             CASE
                 WHEN PH_Close.Comment ~ '^[0-9]+$' THEN CAST(PH_Close.Comment AS int)
                 ELSE NULL
             END = CR.Id
         WHERE PH_Close.PostId = Q.Id AND PH_Close.PostHistoryTypeId = 10
         ORDER BY PH_Close.CreationDate DESC
         LIMIT 1
        ) AS LastCloseReason,
        ARRAY_LENGTH(string_to_array(substring(Q.Tags, 2, LENGTH(Q.Tags)-2), '><'), 1) AS NumberOfTags
    FROM Posts Q
    LEFT JOIN Users U_Q ON Q.OwnerUserId = U_Q.Id
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    LEFT JOIN Users U_A ON A.OwnerUserId = U_A.Id
    LEFT JOIN Votes V ON Q.Id = V.PostId
    WHERE Q.PostTypeId = 1 -- Only questions
),
LinkedPostAnalysis AS (
    SELECT
        P.Id AS PostId,
        COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedCount,
        COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicateCount,
        NULLIF(AVG(COALESCE(RelatedP.Score, 0)), 0) AS AvgRelatedPostScore,
        STRING_AGG(CASE WHEN PL.LinkTypeId = 3 THEN 'DUP:' || RelatedP.Title ELSE NULL END, '; ') FILTER (WHERE RelatedP.Title IS NOT NULL) AS DuplicateTitles
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    LEFT JOIN Posts RelatedP ON (PL.PostId = P.Id AND PL.RelatedPostId = RelatedP.Id) OR (PL.RelatedPostId = P.Id AND PL.PostId = RelatedP.Id)
    GROUP BY P.Id
),
TagFrequency AS (
    SELECT
        LOWER(unnest(string_to_array(substring(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(P.Id) AS PostCount
    FROM Posts P
    WHERE P.Tags IS NOT NULL
    GROUP BY LOWER(unnest(string_to_array(substring(P.Tags, 2, LENGTH(P.Tags)-2), '><')))
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    PQ.QuestionId,
    PQ.QuestionTitle,
    PQ.QuestionScore,
    PQ.QuestionViewCount,
    PQ.QuestionOwnerDisplayName,
    PQ.AnswerId,
    PQ.AnswerScore,
    PQ.AnswerOwnerDisplayName,
    PQ.HasAcceptedAnswer,
    PQ.IsCommunityWiki,
    PQ.LastCloseReason,
    PQ.NumberOfTags,
    LPA.LinkedCount,
    LPA.DuplicateCount,
    LPA.AvgRelatedPostScore,
    COALESCE(LPA.DuplicateTitles, 'No duplicates') AS DuplicateTitles,
    UE.TotalPosts,
    UE.QuestionsAsked,
    UE.AnswersProvided,
    UE.TotalComments,
    UE.TotalBadges,
    UE.GoldBadges,
    UE.TotalEditsMade,
    UE.AveragePostScore AS UserAvgPostScore,
    -- Correlated Subquery: Check if user has 'Guru' badge
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = UE.UserId AND B.Name ILIKE '%Guru%') AS HasGuruBadge,
    -- Correlated Subquery: Average score of questions by the same owner in the same year, excluding current question
    NULLIF((SELECT AVG(P_Other.Score)
     FROM Posts P_Other
     WHERE P_Other.OwnerUserId = PQ.QuestionOwnerId
       AND P_Other.Id != PQ.QuestionId
       AND P_Other.PostTypeId = 1
       AND DATE_PART('year', P_Other.CreationDate) = DATE_PART('year', PQ.QuestionCreationDate)
    ), 0) AS AvgOtherQuestionsScoreSameYear,
    -- Window Function: Rank questions by score within each owner
    RANK() OVER (PARTITION BY PQ.QuestionOwnerId ORDER BY PQ.QuestionScore DESC, PQ.QuestionCreationDate DESC) AS QuestionScoreRankByOwner,
    -- Complex calculation: Engagement Score
    (UE.Reputation * 0.1 + UE.TotalPosts * 0.5 + UE.TotalComments * 0.2 + UE.GoldBadges * 10 + PQ.QuestionScore * 0.8 + PQ.QuestionViewCount * 0.01 + COALESCE(PQ.QuestionFavoriteCount, 0) * 2) AS EngagementScore,
    -- String Expression: Extract first tag and check its frequency
    LOWER(SPLIT_PART(SUBSTRING(PQ.Tags FROM 2 FOR LENGTH(PQ.Tags)-2), '><', 1)) AS FirstTag,
    (SELECT TF.PostCount FROM TagFrequency TF WHERE TF.TagName = LOWER(SPLIT_PART(SUBSTRING(PQ.Tags FROM 2 FOR LENGTH(PQ.Tags)-2), '><', 1))) AS FirstTagPostCount,
    -- NULL logic: Difference between actual answer count and comments count, defaulting to 0 if either is null
    COALESCE(PQ.ActualAnswerCount, 0) - COALESCE(PQ.QuestionCommentCount, 0) AS AnswerCommentDifference,
    -- Conditional expression: Identify potentially "stale" but valuable questions
    CASE
        WHEN PQ.HasAcceptedAnswer = FALSE AND PQ.QuestionScore > 10 AND AGE(NOW(), PQ.QuestionCreationDate) > INTERVAL '1 year' AND PQ.QuestionViewCount > 500 THEN 'High_Score_No_Accepted_Answer_Stale'
        WHEN PQ.ActualAnswerCount = 0 AND PQ.QuestionScore < 0 AND AGE(NOW(), PQ.QuestionCreationDate) < INTERVAL '6 months' THEN 'Low_Score_No_Answers_Recent'
        ELSE 'Normal_Question'
    END AS QuestionStatusCategory,
    'Question-' || PQ.QuestionId AS PostIdentifier,
    'Question' AS RecordType,
    LEAD(PQ.QuestionScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY PQ.QuestionCreationDate) - PQ.QuestionScore AS ScoreChangeToNextQuestion
FROM UserEngagement UE
JOIN PostQualityMetrics PQ ON UE.UserId = PQ.QuestionOwnerId
LEFT JOIN LinkedPostAnalysis LPA ON PQ.QuestionId = LPA.PostId
WHERE UE.Reputation > 1000 -- Filter for more engaged users
  AND PQ.QuestionScore >= 5 -- Filter for questions with some positive score
  AND PQ.QuestionViewCount > 50
  AND (PQ.Tags LIKE '%<sql>%' OR PQ.Tags LIKE '%<database>%') -- Focus on specific tags
  AND LENGTH(PQ.QuestionBody) > 100 -- Ensure substantial body
  AND PQ.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Specific date range
  AND (PQ.LastCloseReason IS NULL OR PQ.LastCloseReason NOT ILIKE '%duplicate%' AND PQ.LastCloseReason NOT ILIKE '%off-topic%') -- Exclude specific close reasons
UNION ALL
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    P.Id AS QuestionId, -- Re-use for answer's parent
    P.Title AS QuestionTitle, -- Re-use for answer's title (if available, otherwise parent's)
    P.Score AS QuestionScore, -- Re-use for answer's score
    P.ViewCount AS QuestionViewCount, -- Re-use for answer's view count (if any)
    U.DisplayName AS QuestionOwnerDisplayName, -- Re-use for answer's owner
    NULL AS AnswerId, -- Not a question, no accepted answer
    NULL AS AnswerScore,
    NULL AS AnswerOwnerDisplayName,
    FALSE AS HasAcceptedAnswer,
    (P.CommunityOwnedDate IS NOT NULL) AS IsCommunityWiki,
    (SELECT
        CASE
            WHEN PH_Close.Comment IS NOT NULL AND LENGTH(TRIM(PH_Close.Comment)) > 0 THEN
                COALESCE(CR.Name, 'Unknown (' || PH_Close.Comment || ')')
            ELSE NULL
        END
     FROM PostHistory PH_Close
     LEFT JOIN CloseReasonTypes CR ON
         CASE
             WHEN PH_Close.Comment ~ '^[0-9]+$' THEN CAST(PH_Close.Comment AS int)
             ELSE NULL
         END = CR.Id
     WHERE PH_Close.PostId = P.Id AND PH_Close.PostHistoryTypeId = 10
     ORDER BY PH_Close.CreationDate DESC
     LIMIT 1
    ) AS LastCloseReason,
    NULL AS NumberOfTags, -- Answers usually don't have tags directly
    LPA.LinkedCount,
    LPA.DuplicateCount,
    LPA.AvgRelatedPostScore,
    COALESCE(LPA.DuplicateTitles, 'No linked posts') AS DuplicateTitles,
    UE.TotalPosts,
    UE.QuestionsAsked,
    UE.AnswersProvided,
    UE.TotalComments,
    UE.TotalBadges,
    UE.GoldBadges,
    UE.TotalEditsMade,
    UE.AveragePostScore AS UserAvgPostScore,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = UE.UserId AND B.Name ILIKE '%Editor%') AS HasEditorBadge, -- Different badge check for non-questions
    NULLIF((SELECT AVG(P_Other.Score)
     FROM Posts P_Other
     WHERE P_Other.OwnerUserId = U.Id
       AND P_Other.Id != P.Id
       AND P_Other.PostTypeId = 2 -- Looking at other answers by the same user
       AND DATE_PART('month', P_Other.CreationDate) = DATE_PART('month', P.CreationDate)
       AND DATE_PART('year', P_Other.CreationDate) = DATE_PART('year', P.CreationDate)
    ), 0) AS AvgOtherAnswersScoreSameMonth,
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS AnswerScoreRankByOwner,
    (UE.Reputation * 0.05 + UE.AnswersProvided * 0.7 + UE.TotalComments * 0.3 + UE.GoldBadges * 5 + P.Score * 0.9 + COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
    NULL AS FirstTag, -- Answers usually don't have tags directly
    NULL AS FirstTagPostCount,
    COALESCE(P.AnswerCount, 0) - COALESCE((SELECT COUNT(Id) FROM Comments WHERE PostId = P.Id), 0) AS AnswerCommentDifference,
    CASE
        WHEN P.Score > 50 AND AGE(NOW(), P.CreationDate) < INTERVAL '3 months' AND P.ParentId IS NOT NULL THEN 'Highly_Scored_Recent_Answer'
        WHEN P.Score < 0 AND AGE(NOW(), P.CreationDate) > INTERVAL '1 year' AND P.ParentId IS NOT NULL THEN 'Low_Score_Old_Answer'
        ELSE 'Normal_Answer'
    END AS PostStatusCategory,
    'Answer-' || P.Id AS PostIdentifier,
    'Answer' AS RecordType,
    LEAD(P.Score, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY P.CreationDate) - P.Score AS ScoreChangeToNextAnswer
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN LinkedPostAnalysis LPA ON P.Id = LPA.PostId
WHERE P.PostTypeId = 2 -- Answers
  AND P.Score >= 1 -- Positive score for answers
  AND LENGTH(P.Body) > 50 -- Substantial body
  AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
  AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = P.ParentId AND Q.ViewCount > 1000 AND Q.AcceptedAnswerId IS NULL) -- Parent question must be popular and still open for accepted answer
ORDER BY EngagementScore DESC, Reputation DESC
LIMIT 1000;
