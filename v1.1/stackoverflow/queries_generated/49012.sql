-- {"query": "49012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2034} 
WITH RecentUserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT V.Id) AS TotalVotesCast,
        MAX(U.LastAccessDate) AS LastSeen
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId AND P.CreationDate >= (NOW() - INTERVAL '18 months')
    LEFT JOIN Comments AS C ON U.Id = C.UserId AND C.CreationDate >= (NOW() - INTERVAL '18 months')
    LEFT JOIN Votes AS V ON U.Id = V.UserId AND V.CreationDate >= (NOW() - INTERVAL '18 months')
    WHERE U.LastAccessDate >= (NOW() - INTERVAL '18 months')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0 OR COUNT(DISTINCT V.Id) > 0
),
UserPostStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS MaxQuestionScore,
        MAX(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS MaxAnswerScore,
        SUM(P.ViewCount) AS TotalViewCount,
        SUM(P.AnswerCount) AS TotalAnswersReceivedOnQuestions
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserPostHistoryMetrics AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN PH.Id END) AS EditEvents, -- Edit Title, Body, Tags, Suggested Edit Applied
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN PH.Id END) AS ModerationEvents -- Post Closed, Post Deleted, Post Locked
    FROM PostHistory AS PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserTopTags AS (
    SELECT
        UserId,
        ARRAY_AGG(TagName ORDER BY QuestionCount DESC, AvgScore DESC) FILTER (WHERE rn <= 5) AS Top5Tags
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
            COUNT(P.Id) AS QuestionCount,
            AVG(P.Score) AS AvgScore,
            ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, AVG(P.Score) DESC) AS rn
        FROM Posts AS P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.OwnerUserId IS NOT NULL
        GROUP BY P.OwnerUserId, TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))
    ) AS TagAgg
    GROUP BY UserId
)
SELECT
    RUA.UserId,
    RUA.DisplayName,
    RUA.Reputation,
    RUA.UpVotes,
    RUA.DownVotes,
    RUA.LastSeen,
    COALESCE(UPS.QuestionsCount, 0) AS TotalQuestions,
    COALESCE(UPS.AnswersCount, 0) AS TotalAnswers,
    COALESCE(UPS.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(UPS.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(UPS.MaxQuestionScore, 0) AS TopQuestionScore,
    COALESCE(UPS.MaxAnswerScore, 0) AS TopAnswerScore,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UPHM.TotalHistoryEvents, 0) AS TotalPostHistoryEvents,
    COALESCE(UPHM.EditEvents, 0) AS PostEditEvents,
    COALESCE(UPHM.ModerationEvents, 0) AS PostModerationEvents,
    COALESCE(UTT.Top5Tags, '{}') AS UsersTopTags,
    -- Calculate a composite engagement score based on weighted factors
    (
        (COALESCE(UPS.AvgQuestionScore, 0) * 0.3) +
        (COALESCE(UPS.AvgAnswerScore, 0) * 0.25) +
        (COALESCE(UBS.GoldBadges, 0) * 10) +
        (COALESCE(UBS.SilverBadges, 0) * 5) +
        (COALESCE(UBS.BronzeBadges, 0) * 1) +
        (COALESCE(RUA.TotalPostsCreated, 0) * 0.5) +
        (COALESCE(RUA.TotalCommentsMade, 0) * 0.1) +
        (COALESCE(RUA.TotalVotesCast, 0) * 0.05) +
        (COALESCE(UPHM.EditEvents, 0) * 0.2) -
        (COALESCE(UPHM.ModerationEvents, 0) * 0.5)
    ) AS EngagementScore,
    -- Rank users by their engagement score, breaking ties by reputation
    ROW_NUMBER() OVER (ORDER BY (
        (COALESCE(UPS.AvgQuestionScore, 0) * 0.3) +
        (COALESCE(UPS.AvgAnswerScore, 0) * 0.25) +
        (COALESCE(UBS.GoldBadges, 0) * 10) +
        (COALESCE(UBS.SilverBadges, 0) * 5) +
        (COALESCE(UBS.BronzeBadges, 0) * 1) +
        (COALESCE(RUA.TotalPostsCreated, 0) * 0.5) +
        (COALESCE(RUA.TotalCommentsMade, 0) * 0.1) +
        (COALESCE(RUA.TotalVotesCast, 0) * 0.05) +
        (COALESCE(UPHM.EditEvents, 0) * 0.2) -
        (COALESCE(UPHM.ModerationEvents, 0) * 0.5)
    ) DESC, RUA.Reputation DESC, RUA.UserId ASC) AS RankByEngagement
FROM RecentUserActivity AS RUA
LEFT JOIN UserPostStats AS UPS ON RUA.UserId = UPS.UserId
LEFT JOIN UserBadgeSummary AS UBS ON RUA.UserId = UBS.UserId
LEFT JOIN UserPostHistoryMetrics AS UPHM ON RUA.UserId = UPHM.UserId
LEFT JOIN UserTopTags AS UTT ON RUA.UserId = UTT.UserId
WHERE RUA.Reputation > 500
ORDER BY RankByEngagement ASC, RUA.Reputation DESC
LIMIT 500;