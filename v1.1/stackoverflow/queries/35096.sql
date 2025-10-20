-- {"query": "35096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 871} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostsCount,
        COUNT(DISTINCT C.Id) AS CommentsCount,
        COUNT(DISTINCT V.Id) AS VotesCount,
        COUNT(DISTINCT B.Id) AS BadgesCount,
        MAX(P.Score) AS MaxPostScore,
        AVG(P.Score) AS AvgPostScore,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.CreationDate) AS LastPostDate,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON P.OwnerUserId = U.Id
    LEFT JOIN Comments C ON C.UserId = U.Id
    LEFT JOIN Votes V ON V.UserId = U.Id
    LEFT JOIN Badges B ON B.UserId = U.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
TopUsers AS (
    SELECT *
    FROM UserActivity
    WHERE ReputationRank <= 50
),
TagStats AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS UsageCount,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT P2.Id) AS TotalPostCount,
        AVG(P2.Score) AS AvgPostScore
    FROM Tags T
    LEFT JOIN Posts P ON position('<' || T.TagName || '>' in P.Tags) > 0
    LEFT JOIN Posts P2 ON position('<' || T.TagName || '>' in P2.Tags) > 0
    GROUP BY T.Id, T.TagName, T.Count
    HAVING COUNT(DISTINCT P.Id) > 100
),
TopQuestions AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.OwnerUserId,
        Q.Score,
        Q.CreationDate,
        Q.ViewCount,
        Q.AnswerCount,
        Q.Tags,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        RANK() OVER (ORDER BY Q.Score DESC) AS ScoreRank,
        RANK() OVER (ORDER BY Q.ViewCount DESC) AS ViewRank
    FROM Posts Q
    LEFT JOIN Votes V ON V.PostId = Q.Id
    WHERE Q.PostTypeId = 1 -- Questions only
      AND Q.Score > 5
      AND Q.ViewCount > 1000
    GROUP BY Q.Id, Q.Title, Q.OwnerUserId, Q.Score, Q.CreationDate, Q.ViewCount, Q.AnswerCount, Q.Tags
)
SELECT
    U.DisplayName AS TopUser,
    U.Reputation,
    U.PostsCount,
    U.CommentsCount,
    U.VotesCount,
    U.BadgesCount,
    U.MaxPostScore,
    U.AvgPostScore,
    Q.Title AS TopScoringQuestion,
    Q.Score AS TopQuestionScore,
    Q.ViewCount AS TopQuestionViews,
    QS.TagName AS MostPopularTagUsed,
    QS.UsageCount AS TagUsage
FROM TopUsers U
LEFT JOIN (
    SELECT DISTINCT ON (OwnerUserId)
        Id, Title, OwnerUserId, Score, ViewCount
    FROM Posts
    WHERE PostTypeId = 1
    ORDER BY OwnerUserId, Score DESC, ViewCount DESC
) Q ON Q.OwnerUserId = U.UserId
LEFT JOIN LATERAL (
    SELECT
        T.TagName,
        COUNT(*) AS UsageCount
    FROM Tags T
    JOIN Posts P ON position('<' || T.TagName || '>' in P.Tags) > 0
    WHERE P.OwnerUserId = U.UserId
    GROUP BY T.TagName
    ORDER BY COUNT(*) DESC
    LIMIT 1
) QS ON true
ORDER BY U.Reputation DESC
LIMIT 20;