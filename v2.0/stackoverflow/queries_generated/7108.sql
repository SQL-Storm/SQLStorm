-- {"query": "7108.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2585} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation > 10000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as RepLevel,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) as RepPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Hot'
            WHEN p.Score > 50 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        COALESCE(AnswerCount, 0) as AnswerCountCorrected,
        COALESCE(p.Tags, '') as TagsCleaned,
        STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ',') AS TagList
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.LastActivityDate, p.Tags, p.PostTypeId
),
TopQuestions AS (
    SELECT 
        pa.Id,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.OwnerUserId,
        pa.ScoreCategory,
        pa.DaysActive,
        pa.TagList,
        NTILE(10) OVER (ORDER BY pa.Score DESC) as ScoreQuintile,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as UserQuestionRank
    FROM PostAnalysis pa
    WHERE pa.Score > 50
),
UserPostPerformance AS (
    SELECT 
        us.Id as UserId,
        us.DisplayName,
        us.Reputation,
        us.RepLevel,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        SUM(pa.Score) as TotalScore,
        AVG(pa.Score) as AvgScore,
        MAX(pa.Score) as MaxScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pa.Score) as MedianScore,
        COUNT(CASE WHEN pa.Score > 100 THEN 1 END) as HotPostCount,
        COUNT(CASE WHEN pa.Score > 50 THEN 1 END) as PopularPostCount,
        COUNT(CASE WHEN pa.PostType = 'Question' THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN pa.PostType = 'Answer' THEN 1 END) as AnswerCount
    FROM UserStats us
    LEFT JOIN PostAnalysis pa ON us.Id = pa.OwnerUserId
    GROUP BY us.Id, us.DisplayName, us.Reputation, us.RepLevel, us.PostCount, us.CommentCount, us.BadgeCount
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        AVG(t.Count) OVER () as AvgTagCount,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count > (SELECT AVG(Count)/2 FROM Tags) THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel
    FROM Tags t
    WHERE t.Count > 100
),
PerformanceMetrics AS (
    SELECT 
        'Overall' as MetricType,
        COUNT(*) as TotalUsers,
        AVG(Reputation) as AvgReputation,
        MAX(Reputation) as MaxReputation,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2021-01-01') as QuestionCount2021,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= '2021-01-01') as AnswerCount2021
    FROM UserStats
UNION ALL
    SELECT 
        'Top Users' as MetricType,
        COUNT(*) as TotalUsers,
        AVG(Reputation) as AvgReputation,
        MAX(Reputation) as MaxReputation,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2021-01-01' AND OwnerUserId IN (SELECT Id FROM UserStats WHERE RepRank <= 100)) as QuestionCount2021,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= '2021-01-01' AND OwnerUserId IN (SELECT Id FROM UserStats WHERE RepRank <= 100)) as AnswerCount2021
    FROM UserStats 
    WHERE RepRank <= 100
)
SELECT 
    upp.UserId,
    upp.DisplayName,
    upp.Reputation,
    upp.RepLevel,
    upp.PostCount,
    upp.CommentCount,
    upp.BadgeCount,
    upp.TotalScore,
    upp.AvgScore,
    upp.MaxScore,
    upp.HotPostCount,
    upp.PopularPostCount,
    upp.QuestionCount,
    upp.AnswerCount,
    CASE WHEN upp.MaxScore > 1000 THEN 'Elite Contributor' ELSE 'Regular Contributor' END as ContributionLevel,
    CASE WHEN upp.QuestionCount > 0 THEN CONCAT('Average Score: ', CAST(upp.AvgScore AS VARCHAR(10))) ELSE 'No Questions' END as QuestionAnalysis,
    COALESCE((SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE t.Count IN (SELECT MAX(Count) FROM Tags WHERE TagName IN (SELECT UNNEST(string_to_array(pa.Tags, '>')) FROM PostAnalysis pa WHERE pa.OwnerUserId = upp.UserId))), 'No Popular Tags') as TopTags,
    (SELECT COUNT(*) FROM TopQuestions tq WHERE tq.OwnerUserId = upp.UserId AND tq.ScoreQuintile <= 2) as HighScoringQuestions,
    (SELECT AVG(tp.Score) FROM PostAnalysis tp JOIN TopQuestions tq ON tp.Id = tq.Id WHERE tq.OwnerUserId = upp.UserId) as AvgHighScoredQuestion,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = upp.UserId AND v.VoteTypeId = 2) as UpVotesReceived,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = upp.UserId AND v.VoteTypeId = 3) as DownVotesReceived,
    CASE 
        WHEN upp.Reputation > 1000 AND upp.PostCount > 50 THEN 'Active'
        WHEN upp.Reputation > 100 AND upp.PostCount > 10 THEN 'Moderate'
        ELSE 'New'
    END as ActivityLevel,
    (SELECT STRING_AGG(CONCAT('Tag:', ts.TagName, ' (', ts.Count, ')'), '; ') 
     FROM Tags ts 
     WHERE ts.Count > (SELECT AVG(Count) FROM Tags) + 200
       AND ts.TagName IN (SELECT UNNEST(string_to_array(pa.Tags, '>')) FROM PostAnalysis pa WHERE pa.OwnerUserId = upp.UserId)) as PopularTags,
    CAST(COUNT(*) AS VARCHAR(10)) as MetricsCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = upp.UserId) as EditingActivity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upp.UserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upp.UserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upp.UserId AND b.Class = 3) as BronzeBadges,
    (SELECT AVG(Reputation) FROM UserStats) as AvgReputationTotal,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = upp.UserId AND ph.PostHistoryTypeId = 2) as BodyEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = upp.UserId AND ph.PostHistoryTypeId = 4) as TitleEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = upp.UserId AND ph.PostHistoryTypeId = 6) as TagsEdits,
    (SELECT MAX(CreationDate) FROM PostHistory ph WHERE ph.UserId = upp.UserId) as LastEditDate,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upp.UserId AND Score > 100) > 0 THEN 'High Scoring Contributor'
        WHEN (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upp.UserId AND Score > 50) > 0 THEN 'Moderate Scoring Contributor'
        ELSE 'Low Scoring Contributor'
    END as ScoringContribution,
    (SELECT STRING_AGG(t1.TagName, ', ') FROM Tags t1 
     WHERE t1.Count = (SELECT MAX(Count) FROM Tags) 
       AND t1.TagName IN (SELECT UNNEST(string_to_array(pa.Tags, '>')) FROM PostAnalysis pa WHERE pa.OwnerUserId = upp.UserId))
    as MostPopularTagInUserPosts,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = upp.UserId) as CommentCountTotal,
    ROW_NUMBER() OVER (ORDER BY upp.TotalScore DESC) as RankingByScore,
    PERCENT_RANK() OVER (ORDER BY upp.TotalScore DESC) as ScorePercentile,
    (SELECT AVG(Reputation) FROM UserStats WHERE RepRank <= 10) as Top10AvgRep,
    (SELECT MAX(Reputation) FROM UserStats WHERE RepRank <= 10) as Top10MaxRep
FROM UserPostPerformance uppers
LEFT JOIN UserStats us ON uppers.UserId = us.Id
LEFT JOIN PostAnalysis pa ON pa.OwnerUserId = uppers.UserId
WHERE uppers.PostCount > 0
GROUP BY 
    uppers.UserId,
    uppers.DisplayName,
    uppers.Reputation,
    uppers.RepLevel,
    uppers.PostCount,
    uppers.CommentCount,
    uppers.BadgeCount,
    uppers.TotalScore,
    uppers.AvgScore,
    uppers.MaxScore,
    uppers.HotPostCount,
    uppers.PopularPostCount,
    uppers.QuestionCount,
    uppers.AnswerCount
HAVING 
    uppers.PostCount > 10 OR uppers.Reputation > 1000
ORDER BY 
    uppers.TotalScore DESC
    OFFSET 0 ROWS
    FETCH NEXT 100 ROWS ONLY;