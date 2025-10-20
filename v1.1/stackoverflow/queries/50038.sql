-- {"query": "50038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1069} 
WITH TagStats AS (
    -- Calculate aggregated statistics for each tag to identify influential ones
    SELECT
        T.TagName,
        T.Count AS PostCount,
        AVG(P.Score) AS AvgScore,
        SUM(P.FavoriteCount) AS TotalFavorites,
        -- Rank tags based on a composite score of count, score, and favorites
        RANK() OVER (ORDER BY T.Count DESC, SUM(P.FavoriteCount) DESC) AS TagRank
    FROM Tags T
    JOIN Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE T.Count > 1000 AND P.FavoriteCount > 100
    GROUP BY T.TagName, T.Count
),
TopUsers AS (
    -- Identify top users based on reputation and engagement metrics
    SELECT
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        (CAST(U.UpVotes AS REAL) / (U.DownVotes + 1)) AS UpDownRatio,
        EXTRACT(YEAR FROM U.CreationDate) AS CreationYear,
        -- Count gold and silver badges for each user
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges
    FROM Users U
    WHERE U.Reputation > 50000 AND U.UpVotes > U.DownVotes
      AND U.Id IN (SELECT OwnerUserId FROM Posts WHERE Score > 100)
),
UserTagContributions AS (
    -- Correlate top users with their contributions to top tags
    SELECT
        P.OwnerUserId,
        TS.TagName,
        COUNT(P.Id) AS PostsInTag,
        SUM(P.Score) AS TotalScoreInTag,
        AVG(P.AnswerCount) AS AvgAnswersPerQuestion,
        SUM(P.ViewCount) AS TotalViewsInTag,
        MAX(P.CreationDate) as LastPostDate
    FROM Posts P
    -- Unnest tags from the'<tag1><tag2>' format to join with TagStats
    CROSS JOIN LATERAL unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS PostTag(TagName)
    JOIN TagStats TS ON PostTag.TagName = TS.TagName
    WHERE P.OwnerUserId IS NOT NULL
      AND TS.TagRank <= 10 -- Focus on the top 10 ranked tags
      AND P.PostTypeId = 1 -- Questions
      AND P.ClosedDate IS NULL
    GROUP BY P.OwnerUserId, TS.TagName
),
AnswerAnalysis AS (
    -- Analyze the quality of answers provided by top users
    SELECT
        A.OwnerUserId,
        AVG(A.Score) AS AvgAnswerScore,
        COUNT(DISTINCT Q.Id) AS AnsweredQuestions,
        -- Calculate the average time it takes for their answers to be posted after the question
        AVG(EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate))) / 3600.0 AS AvgAnswerTimeHours
    FROM Posts A -- Answers
    JOIN Posts Q ON A.ParentId = Q.Id -- Questions
    WHERE A.PostTypeId = 2 -- Answers
      AND A.OwnerUserId IN (SELECT Id FROM TopUsers)
    GROUP BY A.OwnerUserId
)
-- Final result set: Combine all metrics to find the most impactful users in top-tier tags
SELECT
    TU.DisplayName,
    TU.Reputation,
    TU.UpDownRatio,
    TU.GoldBadges,
    TU.SilverBadges,
    UTC.TagName,
    UTC.PostsInTag,
    UTC.TotalScoreInTag,
    UTC.TotalViewsInTag,
    AA.AvgAnswerScore,
    AA.AvgAnswerTimeHours,
    -- Final ranking within each tag based on a weighted score of user and contribution stats
    ROW_NUMBER() OVER(PARTITION BY UTC.TagName ORDER BY (TU.Reputation * 0.2 + UTC.TotalScoreInTag * 0.5 + TU.GoldBadges * 100) DESC) AS UserRankInTag
FROM TopUsers TU
JOIN UserTagContributions UTC ON TU.Id = UTC.OwnerUserId
LEFT JOIN AnswerAnalysis AA ON TU.Id = AA.OwnerUserId
WHERE UTC.PostsInTag > 10 AND AA.AvgAnswerScore > 5
ORDER BY UTC.TagName, UserRankInTag
LIMIT 100;