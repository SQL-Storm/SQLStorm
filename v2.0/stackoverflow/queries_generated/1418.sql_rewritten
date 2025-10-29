-- {"query": "1418.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2484} 
WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersProvided,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreContribution,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        EXTRACT(DAY FROM (MAX(U.LastAccessDate) - U.CreationDate)) AS UserTenureDays, -- PostgreSQL date diff in days
        CASE
            WHEN U.Reputation >= 20000 THEN 'Elite'
            WHEN U.Reputation >= 5000 THEN 'Veteran'
            WHEN U.Reputation >= 500 THEN 'Contributor'
            ELSE 'Newbie'
        END AS ReputationTier,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostInteractionSummary AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.AnswerCount AS QuestionAnswerCount,
        MAX(CASE WHEN A.Id IS NOT NULL THEN 1 ELSE 0 END) AS HasAnswers,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreOnQuestion,
        AVG(CASE WHEN A.PostTypeId = 2 THEN A.Score ELSE NULL END) AS AvgAnswerScoreForQuestion,
        COUNT(CASE WHEN A.PostTypeId = 2 AND A.AcceptedAnswerId IS NOT NULL THEN 1 ELSE NULL END) AS AcceptedAnswersCount,
        EXTRACT(DAY FROM (MIN(CASE WHEN A.PostTypeId = 2 THEN A.CreationDate ELSE NULL END) - Q.CreationDate)) AS TimeToFirstAnswerDays, -- Time to first answer in days
        SUBSTRING(COALESCE(Q.Tags, ''), 2, LENGTH(COALESCE(Q.Tags, '')) - 2) AS CleanedTagsString, -- Store as string, parse later
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsDuplicateSource, -- Is this post a source of a duplicate
        MAX(CASE WHEN Q.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsCommunityWiki
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to this question
    LEFT JOIN Comments C ON Q.Id = C.PostId
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId
    WHERE Q.PostTypeId = 1 -- Only consider questions
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.FavoriteCount, Q.AnswerCount, Q.Tags, Q.CommunityOwnedDate
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS LastCloseReason,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 10) AS LastClosedDate -- PostgreSQL specific FILTER clause
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS TEXT) -- CAST to TEXT for PostgreSQL
    GROUP BY PH.PostId
),
ParsedPostTags AS ( -- CTE for proper tag parsing
    SELECT
        PIS.QuestionId,
        UNNEST(string_to_array(SUBSTRING(PIS.CleanedTagsString, 1, LENGTH(PIS.CleanedTagsString)), '><')) AS TagName
    FROM PostInteractionSummary PIS
    WHERE PIS.CleanedTagsString IS NOT NULL AND LENGTH(PIS.CleanedTagsString) > 0
),
TopQuestionTags AS (
    SELECT
        ppt.TagName,
        COUNT(ppt.QuestionId) AS TagPostCount,
        SUM(P.Score) AS TagTotalScore,
        RANK() OVER (ORDER BY COUNT(ppt.QuestionId) DESC, SUM(P.Score) DESC) AS TagRank
    FROM ParsedPostTags ppt
    JOIN Posts P ON ppt.QuestionId = P.Id
    GROUP BY ppt.TagName
    HAVING COUNT(ppt.QuestionId) > 50 -- Only consider sufficiently popular tags
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    UEM.ReputationTier,
    UEM.TotalPostsCreated,
    UEM.TotalQuestionsAsked,
    UEM.TotalAnswersProvided,
    UEM.UserTenureDays,
    COALESCE(UEM.TotalBadges, 0) AS TotalBadges,
    PIS.QuestionId,
    PIS.QuestionCreationDate,
    PIS.QuestionScore,
    PIS.QuestionViewCount,
    PIS.QuestionFavoriteCount,
    PIS.AvgAnswerScoreForQuestion,
    PIS.TimeToFirstAnswerDays,
    PHD.EditCount AS QuestionEditCount,
    PHD.CloseCount AS QuestionCloseCount,
    PHD.ReopenCount AS QuestionReopenCount,
    PHD.LastCloseReason,
    PIS.CleanedTagsString, -- Keep the original tags string
    TQT.TagName AS TopRelatedTag,
    TQT.TagRank AS TopRelatedTagRank,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY U.Id ORDER BY U.CreationDate) AS RunningUpvoteCount, -- Window function: Running sum of upvotes by user
    AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS AvgPostScoreLast7PostsOfType, -- Window function: Moving average of post scores
    (SELECT AVG(InnerA.Score)
     FROM Posts InnerA
     WHERE InnerA.ParentId = PIS.QuestionId AND InnerA.PostTypeId = 2 AND InnerA.CreationDate > PIS.QuestionCreationDate) AS CorrelatedAvgAnswerScore, -- Correlated subquery for average answer score *after* question creation
    (SELECT COUNT(DISTINCT OtherQ.Id)
     FROM Posts OtherQ
     WHERE OtherQ.PostTypeId = 1
       AND OtherQ.OwnerUserId = U.Id
       AND OtherQ.CreationDate < PIS.QuestionCreationDate
       AND OtherQ.Score > 10
       AND OtherQ.AnswerCount > 2) AS PreviousHighlyEngagedQuestionsCount, -- Correlated subquery: How many high-scoring questions user had before this one
    COALESCE(PIS.IsDuplicateSource, 0) AS IsQuestionDuplicateSourceFlag,
    CASE
        WHEN U.AboutMe LIKE '%developer%' OR U.AboutMe LIKE '%programmer%' THEN 'Developer Profile'
        WHEN U.AboutMe IS NULL OR U.AboutMe = '' THEN 'No Bio'
        ELSE 'Other Profile'
    END AS UserAboutMeCategory, -- String expression with NULL logic
    CASE
        WHEN PIS.QuestionScore > 50 AND PIS.QuestionViewCount > 5000 AND UEM.ReputationTier = 'Elite' THEN 'High Impact Elite Question'
        WHEN PIS.QuestionScore > 10 AND PIS.QuestionAnswerCount > 5 AND UEM.TotalBadges > 10 THEN 'Engaged Contributor Question'
        WHEN PIS.QuestionScore <= 0 OR PIS.QuestionAnswerCount = 0 THEN 'Low Engagement Question'
        ELSE 'Moderate Engagement Question'
    END AS QuestionImpactCategory, -- Complex conditional logic
    NULLIF(U.WebsiteUrl, '') AS CleanedWebsiteUrl -- NULL logic
FROM Users U
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
LEFT JOIN PostInteractionSummary PIS ON U.Id = PIS.OwnerUserId
LEFT JOIN PostHistoryDetails PHD ON PIS.QuestionId = PHD.PostId
LEFT JOIN ParsedPostTags PPT_main ON PIS.QuestionId = PPT_main.QuestionId
LEFT JOIN TopQuestionTags TQT ON PPT_main.TagName = TQT.TagName AND TQT.TagRank <= 5
LEFT JOIN Posts P ON U.Id = P.OwnerUserId -- For the running average window function, needs access to all posts
LEFT JOIN Votes V ON U.Id = V.UserId AND V.PostId = P.Id
WHERE U.Reputation > 1000
  AND U.Views > 50
  AND UEM.TotalQuestionsAsked > 0
  AND PIS.QuestionScore >= 0
  AND P.CreationDate >= '2020-01-01' -- Filter for recent activity
  AND (PHD.CloseCount IS NULL OR PHD.CloseCount < 2) -- Not excessively closed
  AND PIS.TimeToFirstAnswerDays IS NOT NULL AND PIS.TimeToFirstAnswerDays BETWEEN 0 AND 7 -- Answered within a week
  AND (PIS.CleanedTagsString LIKE '%<sql>%' OR PIS.CleanedTagsString LIKE '%<database>%') -- String expression
  AND NOT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Name = 'Disciplined') -- EXISTS/NOT EXISTS subquery
  AND (U.Location IS NOT NULL OR U.WebsiteUrl IS NOT NULL) -- NULL logic
  AND (SELECT MAX(InnerC.Score) FROM Comments InnerC WHERE InnerC.PostId = PIS.QuestionId) > 5 -- Correlated subquery for comment score
ORDER BY U.Reputation DESC, PIS.QuestionScore DESC, UEM.UserTenureDays DESC, RunningUpvoteCount DESC
LIMIT 100;