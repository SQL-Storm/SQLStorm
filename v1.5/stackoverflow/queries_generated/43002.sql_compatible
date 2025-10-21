WITH UserScoreSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
PostActivity AS (
    SELECT
        P.OwnerUserId,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersPosted,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        MAX(P.CreationDate) AS LastActivityDate
    FROM Posts P
    GROUP BY P.OwnerUserId
)
SELECT
    USS.UserId,
    USS.DisplayName,
    USS.Reputation,
    USS.TotalUpvotes,
    USS.TotalDownvotes,
    USS.TotalBadges,
    USS.LastBadgeDate,
    COALESCE(PA.QuestionsPosted, 0) AS QuestionsPosted,
    COALESCE(PA.AnswersPosted, 0) AS AnswersPosted,
    COALESCE(PA.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(PA.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(PA.LastActivityDate, NULL) AS LastActivityDate
FROM UserScoreSummary USS
LEFT JOIN PostActivity PA ON USS.UserId = PA.OwnerUserId
WHERE USS.Reputation > 1000
ORDER BY USS.TotalBadges DESC, PA.QuestionsPosted DESC, USS.Reputation DESC
LIMIT 100;