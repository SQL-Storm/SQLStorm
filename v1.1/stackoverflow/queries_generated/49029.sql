-- {"query": "49029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1603} 

WITH RelevantTags AS (
    SELECT Id, TagName
    FROM Tags
    WHERE TagName IN ('sql', 'python', 'javascript', 'c#', 'java', 'php', 'html', 'css', 'reactjs', 'node.js', 'angular', 'vue.js', 'go', 'ruby', 'android', 'ios', 'machine-learning')
),
HighlyEngagingQuestions AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerId,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.CreationDate AS QuestionCreationDate
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Questions
      AND P.ViewCount > 50000
      AND P.Score > 100
      AND P.CreationDate >= '2020-01-01' -- Focus on recent highly engaging questions
      AND EXISTS (
          SELECT 1
          FROM RelevantTags RT
          WHERE P.Tags LIKE '%' || RT.TagName || '%' -- Case-insensitive tag matching if DB collation supports
      )
),
TopAnswerPosts AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswererUserId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate
    FROM Posts A
    INNER JOIN HighlyEngagingQuestions HEQ ON A.ParentId = HEQ.QuestionId
    WHERE A.PostTypeId = 2 -- Answers
      AND A.OwnerUserId IS NOT NULL
      AND A.CreationDate >= '2020-01-01'
),
AnswererEngagementSummary AS (
    SELECT
        TA.AnswererUserId,
        COUNT(V.Id) AS TotalUpvotesOnAnswers,
        COUNT(DISTINCT TA.QuestionId) AS UniqueQuestionsAnswered,
        SUM(TA.AnswerScore) AS SumAnswerScore,
        AVG(EXTRACT(EPOCH FROM (NOW() - TA.AnswerCreationDate))) AS AvgTimeSinceAnswer
    FROM TopAnswerPosts TA
    INNER JOIN Votes V ON TA.AnswerId = V.PostId
    WHERE V.VoteTypeId = 2 -- UpMod (upvote)
    GROUP BY TA.AnswererUserId
    HAVING COUNT(V.Id) > 50 -- At least 50 upvotes on answers to highly engaging questions
),
UserDuplicateClosures AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS DuplicateClosedQuestionsCount,
        MAX(PH.CreationDate) AS LastDuplicateClosureDate
    FROM Posts P
    INNER JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId = 1 -- Only questions
      AND PH.PostHistoryTypeId = 10 -- Post Closed
      AND PH.Comment IN ('1', '101') -- CloseReasonId for "Duplicate" (old and new)
      AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserQuestionPerformance AS (
    SELECT
        Q.OwnerUserId AS UserId,
        COUNT(Q.Id) AS TotalQuestionsAsked,
        AVG(Q.Score) AS AvgQuestionScore,
        MAX(Q.ViewCount) AS MaxQuestionViewCount,
        SUM(Q.FavoriteCount) AS TotalQuestionFavorites,
        SUM(Q.AnswerCount) AS TotalAnswersToOwnQuestions
    FROM Posts Q
    WHERE Q.PostTypeId = 1
      AND Q.OwnerUserId IS NOT NULL
      AND Q.CreationDate >= '2019-01-01'
    GROUP BY Q.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.UpVotes AS TotalUserUpvotesReceivedOverall,
    U.DownVotes AS TotalUserDownvotesReceivedOverall,
    AES.TotalUpvotesOnAnswers,
    AES.UniqueQuestionsAnswered,
    AES.SumAnswerScore,
    AES.AvgTimeSinceAnswer AS AvgSecondsSinceAnswer,
    COALESCE(UDC.DuplicateClosedQuestionsCount, 0) AS QuestionsClosedAsDuplicate,
    UDC.LastDuplicateClosureDate,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadgesCount,
    COALESCE(UBS.TagBasedBadges, 0) AS TagBasedBadgesCount,
    COALESCE(UQP.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    UQP.AvgQuestionScore,
    UQP.MaxQuestionViewCount,
    COALESCE(UQP.TotalQuestionFavorites, 0) AS TotalQuestionFavorites,
    COALESCE(UQP.TotalAnswersToOwnQuestions, 0) AS TotalAnswersToOwnQuestions,
    DENSE_RANK() OVER (
        ORDER BY
            AES.TotalUpvotesOnAnswers DESC,
            AES.UniqueQuestionsAnswered DESC,
            U.Reputation DESC,
            UQP.AvgQuestionScore DESC,
            COALESCE(UDC.DuplicateClosedQuestionsCount, 0) ASC -- Lower count of duplicate closures preferred
    ) AS EngagementRank,
    NTILE(100) OVER (
        ORDER BY
            AES.TotalUpvotesOnAnswers DESC,
            AES.UniqueQuestionsAnswered DESC,
            U.Reputation DESC
    ) AS PercentileRank
FROM Users U
INNER JOIN AnswererEngagementSummary AES ON U.Id = AES.AnswererUserId
LEFT JOIN UserDuplicateClosures UDC ON U.Id = UDC.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserQuestionPerformance UQP ON U.Id = UQP.UserId
WHERE U.Reputation > 10000 -- Focus on highly reputable users
  AND U.LastAccessDate >= '2023-01-01' -- Recently active users
  AND U.DisplayName IS NOT NULL
  AND U.Location IS NOT NULL
ORDER BY EngagementRank ASC, U.LastAccessDate DESC
LIMIT 200;
