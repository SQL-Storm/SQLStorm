-- {"query": "49036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1471} 

WITH TopPopularTags AS (
    -- Identify the top 200 most frequently used tags overall.
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 200
),
UserGoldBadgeFilter AS (
    -- Pre-filter users who have received at least one gold badge (Class = 1).
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1
),
HighReputationGoldUsers AS (
    -- Select users with high reputation who also possess at least one gold badge.
    SELECT
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.UpVotes,
        U.DownVotes
    FROM Users U
    JOIN UserGoldBadgeFilter UGBF ON U.Id = UGBF.UserId
    WHERE U.Reputation >= 100000
),
EligibleQuestions AS (
    -- Identify questions owned by the 'HighReputationGoldUsers' that meet several criteria:
    --   - Are actual questions (PostTypeId = 1)
    --   - Have a high score, view count, and a good number of answers
    --   - Have an accepted answer and are not closed
    --   - Are associated with at least one tag from the 'TopPopularTags' list
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS UserId,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.CreationDate AS QuestionCreationDate,
        P.AnswerCount AS QuestionAnswerCount
    FROM Posts P
    JOIN HighReputationGoldUsers HRGU ON P.OwnerUserId = HRGU.Id
    WHERE P.PostTypeId = 1
      AND P.Score >= 50
      AND P.ViewCount >= 5000
      AND P.AnswerCount IS NOT NULL AND P.AnswerCount >= 5
      AND P.AcceptedAnswerId IS NOT NULL
      AND P.ClosedDate IS NULL
      AND P.Tags IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM TopPopularTags TPT
          WHERE TPT.TagName IN (SELECT UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')))
      )
),
QuestionHistorySummary AS (
    -- Aggregate the count of distinct significant history events (edits, closes, opens, etc.)
    -- for each 'EligibleQuestion'.
    SELECT
        PH.PostId AS QuestionId,
        COUNT(DISTINCT PH.Id) AS HistoryEventCount
    FROM PostHistory PH
    JOIN EligibleQuestions EQ ON PH.PostId = EQ.QuestionId
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    GROUP BY PH.PostId
),
UserAnswerContributions AS (
    -- Calculate the total number of answers provided and their average score for each user
    -- who has contributed at least 10 answers.
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS TotalAnswersProvided,
        AVG(Score) AS AverageAnswerScore
    FROM Posts
    WHERE PostTypeId = 2 -- Only answers
      AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    HAVING COUNT(Id) >= 10
),
UserCommentActivity AS (
    -- Compute the total number of comments and their average score for comments made by users
    -- on their own questions or answers, requiring at least 20 such comments.
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalSelfComments,
        AVG(C.Score) AS AverageSelfCommentScore
    FROM Comments C
    JOIN Posts P ON C.PostId = P.Id
    WHERE C.UserId = P.OwnerUserId
    GROUP BY C.UserId
    HAVING COUNT(C.Id) >= 20
)
-- Final selection: Retrieve comprehensive details for 'super-contributor' users.
-- These users are high-reputation, gold-badged individuals who have authored multiple
-- eligible questions in popular tags, provided a significant number of answers,
-- engaged in self-commenting, and whose questions have substantial historical activity.
SELECT
    HRGU.Id AS UserId,
    HRGU.DisplayName,
    HRGU.Reputation,
    HRGU.CreationDate AS UserCreationDate,
    HRGU.UpVotes AS TotalUpVotesGiven,
    HRGU.DownVotes AS TotalDownVotesGiven,
    COUNT(DISTINCT EQ.QuestionId) AS NumberOfEligibleQuestions,
    AVG(EQ.QuestionScore) AS AvgEligibleQuestionScore,
    AVG(EQ.QuestionViewCount) AS AvgEligibleQuestionViewCount,
    SUM(COALESCE(QHS.HistoryEventCount, 0)) AS TotalHistoryEventsOnQuestions,
    UAC.TotalAnswersProvided,
    UAC.AverageAnswerScore,
    UCA.TotalSelfComments,
    UCA.AverageSelfCommentScore,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = HRGU.Id AND B.Class = 1) AS GoldBadgeCount
FROM HighReputationGoldUsers HRGU
JOIN EligibleQuestions EQ ON HRGU.Id = EQ.UserId
LEFT JOIN QuestionHistorySummary QHS ON EQ.QuestionId = QHS.QuestionId
LEFT JOIN UserAnswerContributions UAC ON HRGU.Id = UAC.UserId
LEFT JOIN UserCommentActivity UCA ON HRGU.Id = UCA.UserId
WHERE UAC.UserId IS NOT NULL -- Exclude users who don't meet answer contribution criteria
  AND UCA.UserId IS NOT NULL -- Exclude users who don't meet self-comment activity criteria
GROUP BY
    HRGU.Id,
    HRGU.DisplayName,
    HRGU.Reputation,
    HRGU.CreationDate,
    HRGU.UpVotes,
    HRGU.DownVotes,
    UAC.TotalAnswersProvided,
    UAC.AverageAnswerScore,
    UCA.TotalSelfComments,
    UCA.AverageSelfCommentScore
HAVING COUNT(DISTINCT EQ.QuestionId) >= 5 -- Users must have authored at least 5 eligible questions
ORDER BY
    HRGU.Reputation DESC,
    NumberOfEligibleQuestions DESC,
    TotalHistoryEventsOnQuestions DESC
LIMIT 100;
