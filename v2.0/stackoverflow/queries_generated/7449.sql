-- {"query": "7449.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1979} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(p.Score) AS MaxPostScore,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT LEFT(p.Title, 50), ' | ') AS SampleTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END, ' | ') AS SampleTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
      AND u.Reputation > 1000
      AND u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY Views DESC) AS ViewRank,
        NTILE(10) OVER (ORDER BY UpVotes DESC) AS UpVoteDecile,
        CASE 
            WHEN Reputation > 100000 THEN 'Elite'
            WHEN Reputation > 50000 THEN 'Veteran'
            WHEN Reputation > 10000 THEN 'Experienced'
            ELSE 'Regular'
        END AS ReputationLevel,
        COALESCE(SampleTitles, 'No Titles') AS TitleList,
        COALESCE(SampleTags, 'No Tags') AS TagList
    FROM UserActivity
),
UserPostStats AS (
    SELECT 
        ru.UserId,
        ru.UserRank,
        ru.ReputationLevel,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore,
        STRING_AGG(
            COALESCE(CONCAT('Q:', p.Title, ' (', p.Score, ')'), 'A: Answer'), 
            ' | '
        ) AS PostsSummary,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastActivity
    FROM RankedUsers ru
    JOIN Posts p ON ru.UserId = p.OwnerUserId
    WHERE p.CreationDate >= '2015-01-01'
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    GROUP BY ru.UserId, ru.UserRank, ru.ReputationLevel
),
ComplexActivity AS (
    SELECT 
        ups.UserId,
        ups.UserRank,
        ups.ReputationLevel,
        ups.PostCount,
        ups.AvgScore,
        ups.MaxScore,
        ups.PostsSummary,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.LastActivity,
        ROW_NUMBER() OVER (PARTITION BY ups.ReputationLevel ORDER BY ups.AvgScore DESC) AS LevelRank,
        PERCENT_RANK() OVER (ORDER BY ups.AvgScore) AS ScorePercentile,
        (ups.PostCount * ups.AvgScore) / NULLIF(ups.QuestionCount, 0) AS EfficiencyFactor,
        CASE 
            WHEN ups.AnswerCount > ups.QuestionCount THEN 'Active Answerer'
            WHEN ups.QuestionCount > ups.AnswerCount THEN 'Active Questioner'
            ELSE 'Balanced'
        END AS ActivityType,
        LAG(ups.AvgScore, 1) OVER (ORDER BY ups.UserRank) AS PreviousRankAvgScore,
        LEAD(ups.AvgScore, 1) OVER (ORDER BY ups.UserRank) AS NextRankAvgScore
    FROM UserPostStats ups
),
FinalAnalysis AS (
    SELECT 
        ca.UserId,
        ca.UserRank,
        ca.ReputationLevel,
        ca.PostCount,
        ca.AvgScore,
        ca.MaxScore,
        ca.PostsSummary,
        ca.QuestionCount,
        ca.AnswerCount,
        ca.LastActivity,
        ca.LevelRank,
        ca.ScorePercentile,
        ca.EfficiencyFactor,
        ca.ActivityType,
        ca.PreviousRankAvgScore,
        ca.NextRankAvgScore,
        ISNULL(ca.PreviousRankAvgScore, 0) - ISNULL(ca.NextRankAvgScore, 0) AS ScoreDifference,
        ABS(ISNULL(ca.EfficiencyFactor, 0)) AS AbsEfficiency,
        CASE 
            WHEN ca.ScorePercentile > 0.9 THEN 'Top Tier'
            WHEN ca.ScorePercentile > 0.7 THEN 'High Tier'
            WHEN ca.ScorePercentile > 0.5 THEN 'Medium Tier'
            ELSE 'Lower Tier'
        END AS PerformanceTier,
        IIF(ca.ActivityType = 'Active Answerer', 1, 0) AS IsAnswerer,
        IIF(ca.ActivityType = 'Active Questioner', 1, 0) AS IsQuestioner,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.UserId AND v.VoteTypeId IN (2, 3)) AS VoteCount,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p JOIN Votes v ON p.Id = v.PostId WHERE v.UserId = ca.UserId AND v.VoteTypeId = 2) AS UpvotesReceived,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p JOIN Votes v ON p.Id = v.PostId WHERE v.UserId = ca.UserId AND v.VoteTypeId = 3) AS DownvotesReceived
    FROM ComplexActivity ca
),
CombinedResult AS (
    SELECT 
        fa.UserId,
        fa.UserRank,
        fa.ReputationLevel,
        fa.PostCount,
        fa.AvgScore,
        fa.MaxScore,
        fa.QuestionCount,
        fa.AnswerCount,
        fa.LastActivity,
        fa.LevelRank,
        fa.ScorePercentile,
        fa.EfficiencyFactor,
        fa.ActivityType,
        fa.ScoreDifference,
        fa.AbsEfficiency,
        fa.PerformanceTier,
        fa.IsAnswerer,
        fa.IsQuestioner,
        fa.VoteCount,
        fa.UpvotesReceived,
        fa.DownvotesReceived,
        ROW_NUMBER() OVER (ORDER BY fa.EfficiencyFactor DESC) AS EfficiencyRank,
        DENSE_RANK() OVER (ORDER BY fa.ScorePercentile DESC) AS PercentileRank
    FROM FinalAnalysis fa
)
SELECT 
    cr.UserId,
    cr.UserRank,
    cr.ReputationLevel,
    cr.PostCount,
    cr.AvgScore,
    cr.MaxScore,
    cr.QuestionCount,
    cr.AnswerCount,
    cr.LastActivity,
    cr.LevelRank,
    cr.ScorePercentile,
    cr.EfficiencyFactor,
    cr.ActivityType,
    cr.ScoreDifference,
    cr.AbsEfficiency,
    cr.PerformanceTier,
    cr.IsAnswerer,
    cr.IsQuestioner,
    cr.VoteCount,
    cr.UpvotesReceived,
    cr.DownvotesReceived,
    cr.EfficiencyRank,
    cr.PercentileRank,
    CASE 
        WHEN cr.EfficiencyFactor > (SELECT AVG(EfficiencyFactor) FROM CombinedResult) THEN 'Above Average'
        WHEN cr.EfficiencyFactor < (SELECT AVG(EfficiencyFactor) FROM CombinedResult) THEN 'Below Average'
        ELSE 'Average'
    END AS EfficiencyStatus,
    CASE 
        WHEN cr.ScorePercentile > 0.8 AND cr.ReputationLevel IN ('Elite', 'Veteran') THEN 'Highly Active'
        WHEN cr.ScorePercentile > 0.5 AND cr.ReputationLevel IN ('Experienced', 'Regular') THEN 'Moderately Active'
        ELSE 'Low Activity'
    END AS ActivityStatus,
    ISNULL(cr.ScoreDifference, 0) AS DifferenceFromNeighbors,
    CASE 
        WHEN cr.PostCount > 100 THEN 'Heavy Poster'
        WHEN cr.PostCount > 50 THEN 'Regular Poster'
        WHEN cr.PostCount > 10 THEN 'Occasional Poster'
        ELSE 'Rare Poster'
    END AS PosterFrequency,
    COALESCE(
        CASE WHEN cr.VoteCount > 100 THEN 1 ELSE 0 END +
        CASE WHEN cr.UpvotesReceived > 50 THEN 1 ELSE 0 END +
        CASE WHEN cr.DownvotesReceived > 20 THEN 1 ELSE 0 END +
        CASE WHEN cr.AnswerCount > 10 THEN 1 ELSE 0 END,
        0
    ) AS ActivityScore
FROM CombinedResult cr
WHERE cr.PostCount >= 5
  AND cr.UserRank <= 1000
  AND cr.LastActivity >= DATEADD(YEAR, -2, GETDATE())
  AND cr.EfficiencyFactor IS NOT NULL
ORDER BY cr.EfficiencyFactor DESC, cr.AvgScore DESC
OPTION (MAXDOP 4, RECOMPILE);