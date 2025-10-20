-- {"query": "49060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1391} 

WITH UserInfluence AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes AS TotalUpVotes,
        COUNT(DISTINCT A.Id) AS HighScoringAcceptedAnswersCount
    FROM Users AS U
    LEFT JOIN Posts AS A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2 AND A.Score >= 10
    LEFT JOIN Posts AS Q ON A.Id = Q.AcceptedAnswerId AND Q.PostTypeId = 1
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes
),
UserModerationActivity AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS CloseReopenEventsCount
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11) -- 10 = Post Closed, 11 = Post Reopened
    GROUP BY PH.UserId
),
CombinedUserMetrics AS (
    SELECT
        UI.UserId,
        UI.DisplayName,
        UI.Reputation,
        UI.TotalUpVotes,
        UI.HighScoringAcceptedAnswersCount,
        COALESCE(UMA.CloseReopenEventsCount, 0) AS CloseReopenEventsCount,
        (
            UI.Reputation * 0.01 +
            UI.TotalUpVotes * 0.1 +
            UI.HighScoringAcceptedAnswersCount * 5 +
            COALESCE(UMA.CloseReopenEventsCount, 0) * 10
        ) AS TotalInfluenceScore
    FROM UserInfluence AS UI
    LEFT JOIN UserModerationActivity AS UMA ON UI.UserId = UMA.UserId
),
TopInfluentialUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        TotalUpVotes,
        HighScoringAcceptedAnswersCount,
        CloseReopenEventsCount,
        TotalInfluenceScore,
        ROW_NUMBER() OVER (ORDER BY TotalInfluenceScore DESC, Reputation DESC) AS Rank
    FROM CombinedUserMetrics
    WHERE DisplayName IS NOT NULL
    ORDER BY TotalInfluenceScore DESC, Reputation DESC
    LIMIT 20
),
UserQuestionTagsRaw AS (
    SELECT
        TIU.UserId,
        P.Id AS PostId,
        P.Score AS PostScore,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    INNER JOIN TopInfluentialUsers AS TIU ON P.OwnerUserId = TIU.UserId
    WHERE P.PostTypeId = 1
      AND P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
),
UserAnswersData AS (
    SELECT
        TIU.UserId,
        P.Id AS AnswerId,
        P.Score AS AnswerScore,
        P.ParentId AS ParentQuestionId
    FROM Posts AS P
    INNER JOIN TopInfluentialUsers AS TIU ON P.OwnerUserId = TIU.UserId
    WHERE P.PostTypeId = 2
),
UserTagPostScores AS (
    SELECT
        UQT.UserId,
        UQT.TagName,
        UQT.PostId AS QuestionId,
        UQT.PostScore AS QuestionScore,
        NULL::INT AS AnswerId,
        NULL::INT AS AnswerScore
    FROM UserQuestionTagsRaw AS UQT

    UNION ALL

    SELECT
        UAD.UserId,
        UQT.TagName,
        UQT.PostId AS QuestionId,
        NULL::INT AS QuestionScore,
        UAD.AnswerId,
        UAD.AnswerScore
    FROM UserAnswersData AS UAD
    INNER JOIN UserQuestionTagsRaw AS UQT ON UAD.ParentQuestionId = UQT.PostId AND UAD.UserId = UQT.UserId
),
UserTagAggregates AS (
    SELECT
        UTPS.UserId,
        UTPS.TagName,
        COUNT(DISTINCT UTPS.QuestionId) FILTER (WHERE UTPS.QuestionScore IS NOT NULL) AS QuestionsCount,
        AVG(UTPS.QuestionScore) FILTER (WHERE UTPS.QuestionScore IS NOT NULL) AS AvgQuestionScore,
        COUNT(DISTINCT UTPS.AnswerId) FILTER (WHERE UTPS.AnswerScore IS NOT NULL) AS AnswersCount,
        AVG(UTPS.AnswerScore) FILTER (WHERE UTPS.AnswerScore IS NOT NULL) AS AvgAnswerScore,
        COUNT(DISTINCT UTPS.QuestionId) + COUNT(DISTINCT UTPS.AnswerId) AS TotalPostsWithTag
    FROM UserTagPostScores AS UTPS
    GROUP BY UTPS.UserId, UTPS.TagName
),
RankedUserTags AS (
    SELECT
        UTA.UserId,
        UTA.TagName,
        UTA.QuestionsCount,
        UTA.AvgQuestionScore,
        UTA.AnswersCount,
        UTA.AvgAnswerScore,
        UTA.TotalPostsWithTag,
        ROW_NUMBER() OVER (PARTITION BY UTA.UserId ORDER BY UTA.TotalPostsWithTag DESC, (COALESCE(UTA.AvgQuestionScore, 0) + COALESCE(UTA.AvgAnswerScore, 0)) DESC) AS TagRank
    FROM UserTagAggregates AS UTA
)
SELECT
    TIU.Rank,
    TIU.DisplayName AS UserName,
    TIU.Reputation,
    TIU.TotalUpVotes,
    TIU.HighScoringAcceptedAnswersCount,
    TIU.CloseReopenEventsCount,
    TIU.TotalInfluenceScore,
    RUT.TagName AS TopActiveTag,
    RUT.QuestionsCount AS TagQuestionsCount,
    RUT.AvgQuestionScore AS TagAvgQuestionScore,
    RUT.AnswersCount AS TagAnswersCount,
    RUT.AvgAnswerScore AS TagAvgAnswerScore
FROM TopInfluentialUsers AS TIU
LEFT JOIN RankedUserTags AS RUT ON TIU.UserId = RUT.UserId AND RUT.TagRank <= 3
ORDER BY TIU.Rank, RUT.TagRank;
