-- {"query": "49019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1167} 

WITH RecentHighImpactQuestions AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Score AS QuestionScore,
        Q.ViewCount
    FROM Posts Q
    WHERE
        Q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
        AND Q.CreationDate >= NOW() - INTERVAL '7 years'
        AND (
            Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<database>%' OR Q.Tags LIKE '%<performance>%'
        )
        AND Q.ViewCount > (
            SELECT AVG(P.ViewCount)
            FROM Posts P
            WHERE P.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
              AND P.CreationDate >= NOW() - INTERVAL '7 years'
              AND P.ViewCount IS NOT NULL
              AND P.ViewCount > 0
        )
),
ContributingAnswers AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate
    FROM Posts A
    INNER JOIN RecentHighImpactQuestions RHQ ON A.ParentId = RHQ.QuestionId
    WHERE A.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
),
AnswerDetailedVotes AS (
    SELECT
        V.PostId AS AnswerId,
        SUM(CASE WHEN V.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Votes V
    INNER JOIN ContributingAnswers CA ON V.PostId = CA.AnswerId
    GROUP BY V.PostId
),
UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes AS TotalUserUpvotesGiven,
        U.DownVotes AS TotalUserDownvotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(U.LastAccessDate) AS LastSeen
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
),
PostHistoryDetails AS (
    SELECT
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Initial Body'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Body'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Deleted')
    )
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalBadgesEarned,
    UAS.TotalCommentsMade,
    SUM(COALESCE(ADV.UpvoteCount, 0)) AS TotalReceivedUpvotesOnContributingAnswers,
    SUM(COALESCE(ADV.DownvoteCount, 0)) AS TotalReceivedDownvotesOnContributingAnswers,
    AVG(CA.AnswerScore) AS AverageAnswerScoreForRelevantQuestions,
    COUNT(DISTINCT CA.AnswerId) AS NumberOfContributingAnswers,
    MIN(CA.AnswerCreationDate) AS FirstAnswerDate,
    MAX(CA.AnswerCreationDate) AS LastAnswerDate,
    MAX(PHD.HistoryDate) AS LatestPostEditOrDeletionDate
FROM UserActivitySummary UAS
INNER JOIN ContributingAnswers CA ON UAS.UserId = CA.AnswerOwnerId
LEFT JOIN AnswerDetailedVotes ADV ON CA.AnswerId = ADV.AnswerId
LEFT JOIN PostHistoryDetails PHD ON UAS.UserId = PHD.UserId AND CA.AnswerId = PHD.PostId
WHERE UAS.Reputation > 1000
  AND NOT EXISTS (
      SELECT 1 FROM PostHistoryDetails PHD_DEL
      WHERE PHD_DEL.UserId = UAS.UserId
        AND PHD_DEL.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Deleted')
      GROUP BY PHD_DEL.UserId
      HAVING COUNT(PHD_DEL.PostId) > 5 -- Users who have deleted more than 5 posts
  )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalBadgesEarned,
    UAS.TotalCommentsMade
HAVING COUNT(DISTINCT CA.AnswerId) >= 5 -- Only users with at least 5 contributing answers
ORDER BY
    TotalReceivedUpvotesOnContributingAnswers DESC,
    UAS.Reputation DESC,
    NumberOfContributingAnswers DESC
LIMIT 20;
