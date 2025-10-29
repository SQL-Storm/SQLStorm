WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE WHEN p.Score > 0 THEN 'High' WHEN p.Score > -5 THEN 'Medium' ELSE 'Low' END AS ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        NTILE(10) OVER (ORDER BY p.Score) AS ScoreDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.PostId) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.PostId END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.PostId END) AS AnswerCount,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastActivityDate,
        STRING_AGG(CASE WHEN ps.PostTypeId = 1 THEN ps.Title END, ' | ') AS RecentQuestions,
        STRING_AGG(CASE WHEN ps.PostTypeId = 2 THEN ps.Title END, ' | ') AS RecentAnswers
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.Count > 1000 THEN 'Popular' ELSE 'Moderate' END AS TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    WHERE t.Count > 50
),
ComplexFilter AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.UserPostRank,
        ps.PrevScore,
        ps.AvgUserScore,
        ps.GlobalScoreRank,
        ps.ScoreDecile,
        ps.ScoreCategory,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.ParentId,
        ps.AcceptedAnswerId,
        CASE 
            WHEN ps.Score > ps.AvgUserScore AND ps.Score > 10 THEN 'AboveAvgHighScore'
            WHEN ps.Score > ps.AvgUserScore THEN 'AboveAvg'
            WHEN ps.Score < ps.AvgUserScore AND ps.Score < -5 THEN 'BelowAvgLowScore'
            WHEN ps.Score < ps.AvgUserScore THEN 'BelowAvg'
            ELSE 'Normal'
        END AS ScorePerformance,
        CASE 
            WHEN ps.UserPostRank = 1 THEN 'FirstPost'
            WHEN ps.UserPostRank = 2 THEN 'SecondPost'
            WHEN ps.Score > 50 AND ps.ViewCount > 1000 THEN 'Viral'
            WHEN ps.Score > 100 THEN 'HighlyRated'
            ELSE 'Regular'
        END AS PostClassification,
        ps.PostTypeId
    FROM PostStats ps
    WHERE ps.Score IS NOT NULL
),
UserComplexCalc AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastActivityDate,
        CASE 
            WHEN ua.Reputation > 10000 THEN 'Elite'
            WHEN ua.Reputation > 5000 THEN 'Veteran'
            WHEN ua.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END AS UserLevel,
        CASE 
            WHEN ua.QuestionCount > 50 AND ua.AnswerCount > 100 THEN 'ProActive'
            WHEN ua.QuestionCount > 20 THEN 'Questioner'
            WHEN ua.AnswerCount > 50 THEN 'Helper'
            ELSE 'Regular'
        END AS ActivityType,
        ROW_NUMBER() OVER (ORDER BY ua.TotalScore DESC) AS TopScoreRank,
        RANK() OVER (ORDER BY ua.Reputation DESC) AS TopReputationRank
    FROM UserActivity ua
),
DetailedAnalysis AS (
    SELECT 
        cf.PostId,
        cf.OwnerUserId,
        cf.Score,
        cf.ViewCount,
        cf.AnswerCount,
        cf.CommentCount,
        cf.FavoriteCount,
        cf.UserPostRank,
        cf.PrevScore,
        cf.AvgUserScore,
        cf.GlobalScoreRank,
        cf.ScoreDecile,
        cf.ScoreCategory,
        cf.CreationDate,
        cf.Title,
        cf.Tags,
        cf.ParentId,
        cf.AcceptedAnswerId,
        cf.ScorePerformance,
        cf.PostClassification,
        u.UserLevel,
        u.ActivityType,
        u.TopScoreRank,
        u.TopReputationRank,
        CASE 
            WHEN cf.Score > 0 AND cf.ViewCount > 100 AND cf.AnswerCount > 0 THEN 'ViralQuestion'
            WHEN cf.Score > 0 AND cf.ViewCount > 500 THEN 'PopularQuestion'
            WHEN cf.Score < 0 AND cf.ViewCount > 500 THEN 'ControversialQuestion'
            WHEN cf.PostTypeId = 2 AND cf.Score > 5 THEN 'HelpfulAnswer'
            WHEN cf.PostTypeId = 2 AND cf.Score > 0 AND cf.ViewCount > 100 THEN 'UsefulAnswer'
            ELSE 'Regular'
        END AS ContentCategory,
        CASE 
            WHEN cf.Tags IS NOT NULL AND cf.Tags LIKE '%<%' THEN 
                (SELECT COUNT(*) FROM (
                    SELECT trim(tag) AS tag FROM (SELECT 1) v CROSS JOIN LATERAL (
                        SELECT unnest(string_to_array(substring(cf.Tags FROM 2 FOR char_length(cf.Tags)-2), '><')) AS tag
                    ) s
                ) q)
            ELSE 0
        END AS TagCount,
        COALESCE(cf.Score - cf.PrevScore, 0) AS ScoreChange,
        CASE 
            WHEN cf.PostClassification IN ('Viral', 'HighlyRated') AND cf.ViewCount > 1000 THEN 'Extreme'
            WHEN cf.PostClassification IN ('Viral', 'HighlyRated') THEN 'High'
            WHEN cf.PostClassification IN ('AboveAvgHighScore', 'AboveAvg') THEN 'Medium'
            ELSE 'Low'
        END AS ImpactLevel,
        CASE 
            WHEN cf.Score > 5 AND cf.ViewCount > 500 AND cf.AnswerCount > 2 THEN 'WellAnswered'
            WHEN cf.Score > 3 AND cf.AnswerCount > 0 THEN 'ModeratelyAnswered'
            WHEN cf.Score > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        DENSE_RANK() OVER (PARTITION BY cf.OwnerUserId ORDER BY cf.CreationDate) AS PostSequence
    FROM ComplexFilter cf
    JOIN UserComplexCalc u ON cf.OwnerUserId = u.UserId
    WHERE cf.Score IS NOT NULL
),
AdvancedMetrics AS (
    SELECT 
        da.PostId,
        da.OwnerUserId,
        da.Score,
        da.ViewCount,
        da.AnswerCount,
        da.CommentCount,
        da.FavoriteCount,
        da.UserPostRank,
        da.PrevScore,
        da.AvgUserScore,
        da.GlobalScoreRank,
        da.ScoreDecile,
        da.ScoreCategory,
        da.CreationDate,
        da.Title,
        da.Tags,
        da.ParentId,
        da.AcceptedAnswerId,
        da.ScorePerformance,
        da.PostClassification,
        da.UserLevel,
        da.ActivityType,
        da.TopScoreRank,
        da.TopReputationRank,
        da.ContentCategory,
        da.TagCount,
        da.ScoreChange,
        da.ImpactLevel,
        da.AnswerStatus,
        da.PostSequence,
        CASE 
            WHEN da.Score > (SELECT AVG(x.Score) FROM DetailedAnalysis x) THEN 1
            WHEN da.Score < (SELECT AVG(x.Score) FROM DetailedAnalysis x) THEN -1
            ELSE 0
        END AS ScoreVsAverage,
        CASE 
            WHEN da.ViewCount > (SELECT AVG(x.ViewCount) FROM DetailedAnalysis x) THEN 1
            WHEN da.ViewCount < (SELECT AVG(x.ViewCount) FROM DetailedAnalysis x) THEN -1
            ELSE 0
        END AS ViewsVsAverage,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId = da.PostId AND p.PostTypeId = 2) THEN 1
            ELSE 0
        END AS HasAnswers,
        CASE 
            WHEN da.Tags IS NOT NULL AND da.Tags <> '' THEN 
                (SELECT STRING_AGG(tag, ', ') FROM (
                    SELECT trim(tag) AS tag FROM (SELECT 1) v CROSS JOIN LATERAL (
                        SELECT unnest(string_to_array(substring(da.Tags FROM 2 FOR char_length(da.Tags)-2), '><')) AS tag
                    ) s
                ) t)
            ELSE NULL
        END AS ExtractedTags,
        LAG(da.Score, 1) OVER (PARTITION BY da.OwnerUserId ORDER BY da.CreationDate) AS PreviousScore,
        LEAD(da.Score, 1) OVER (PARTITION BY da.OwnerUserId ORDER BY da.CreationDate) AS NextScore,
        ABS(da.Score - LAG(da.Score, 1) OVER (PARTITION BY da.OwnerUserId ORDER BY da.CreationDate)) AS ScoreVariation,
        CASE 
            WHEN da.ScoreChange > 10 THEN 'HighGrowth'
            WHEN da.ScoreChange < -10 THEN 'HighDecline'
            WHEN da.ScoreChange > 0 THEN 'PositiveChange'
            WHEN da.ScoreChange < 0 THEN 'NegativeChange'
            ELSE 'Stable'
        END AS TrendAnalysis
    FROM DetailedAnalysis da
),
FinalAnalysis AS (
    SELECT
        am.PostId,
        am.OwnerUserId,
        am.Score,
        am.ViewCount,
        am.AnswerCount,
        am.CommentCount,
        am.FavoriteCount,
        am.UserPostRank,
        am.PrevScore,
        am.AvgUserScore,
        am.GlobalScoreRank,
        am.ScoreDecile,
        am.ScoreCategory,
        am.CreationDate,
        am.Title,
        am.Tags,
        am.ParentId,
        am.AcceptedAnswerId,
        am.ScorePerformance,
        am.PostClassification,
        am.UserLevel,
        am.ActivityType,
        am.TopScoreRank,
        am.TopReputationRank,
        am.ContentCategory,
        am.TagCount AS TagCountFromDetailed,
        am.ScoreChange,
        am.ImpactLevel,
        am.AnswerStatus,
        am.PostSequence,
        am.ScoreVsAverage,
        am.ViewsVsAverage,
        am.HasAnswers,
        am.ExtractedTags,
        am.PreviousScore,
        am.NextScore,
        am.ScoreVariation,
        am.TrendAnalysis,
        ta.TagName,
        ta.Count AS TagCount,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.TagPopularity,
        ta.PopularityRank,
        CASE 
            WHEN am.Tags IS NOT NULL AND am.Tags <> '' THEN 
                (SELECT COUNT(*) FROM (
                    SELECT trim(tag) AS tag FROM (SELECT 1) v CROSS JOIN LATERAL (
                        SELECT unnest(string_to_array(substring(am.Tags FROM 2 FOR char_length(am.Tags)-2), '><')) AS tag
                    ) s
                ) q)
            ELSE 0
        END AS TotalTags,
        CASE 
            WHEN am.Tags IS NOT NULL AND am.Tags <> '' THEN 
                (SELECT STRING_AGG(tag, ', ') FROM (
                    SELECT trim(tag) AS tag FROM (SELECT 1) v CROSS JOIN LATERAL (
                        SELECT unnest(string_to_array(substring(am.Tags FROM 2 FOR char_length(am.Tags)-2), '><')) AS tag
                    ) s
                ) t
                )
            ELSE NULL
        END AS SampleTags,
        ROW_NUMBER() OVER (ORDER BY am.Score DESC) AS RowNum,
        COUNT(*) OVER () AS TotalRows
    FROM AdvancedMetrics am
    LEFT JOIN TagAnalysis ta ON EXISTS (
        SELECT 1 FROM (SELECT 1) v CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(substring(am.Tags FROM 2 FOR char_length(am.Tags)-2), '><')) AS tag
        ) s
        WHERE s.tag = ta.TagName
    )
)
SELECT 
    fa.PostId,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.UserPostRank,
    fa.PrevScore,
    fa.AvgUserScore,
    fa.GlobalScoreRank,
    fa.ScoreDecile,
    fa.ScoreCategory,
    fa.CreationDate,
    fa.Title,
    fa.Tags,
    fa.ParentId,
    fa.AcceptedAnswerId,
    fa.ScorePerformance,
    fa.PostClassification,
    fa.UserLevel,
    fa.ActivityType,
    fa.TopScoreRank,
    fa.TopReputationRank,
    fa.ContentCategory,
    fa.TagCount,
    fa.ScoreChange,
    fa.ImpactLevel,
    fa.AnswerStatus,
    fa.PostSequence,
    fa.ScoreVsAverage,
    fa.ViewsVsAverage,
    fa.HasAnswers,
    fa.ExtractedTags,
    fa.PreviousScore,
    fa.NextScore,
    fa.ScoreVariation,
    fa.TrendAnalysis,
    fa.TagName,
    fa.TagPopularity,
    fa.PopularityRank,
    fa.TotalTags,
    fa.SampleTags,
    fa.RowNum,
    fa.TotalRows,
    CASE 
        WHEN fa.Score < 0 THEN 'Poor'
        WHEN fa.Score BETWEEN 0 AND 5 THEN 'Fair'
        WHEN fa.Score BETWEEN 6 AND 20 THEN 'Good'
        WHEN fa.Score BETWEEN 21 AND 100 THEN 'VeryGood'
        WHEN fa.Score > 100 THEN 'Excellent'
        ELSE 'Undefined'
    END AS Rating,
    CASE 
        WHEN fa.ViewCount > 1000 THEN 'Viral'
        WHEN fa.ViewCount > 500 THEN 'Popular'
        WHEN fa.ViewCount > 100 THEN 'Notable'
        WHEN fa.ViewCount > 0 THEN 'SomeInterest'
        ELSE 'NoViews'
    END AS Popularity,
    CAST((fa.Score * 100.0 / NULLIF(fa.GlobalScoreRank, 0)) AS DECIMAL(10,2)) AS ScoreToRankRatio,
    ROUND((100.0 * (fa.Score - (SELECT MIN(x.Score) FROM FinalAnalysis x))) / NULLIF((SELECT MAX(x.Score) FROM FinalAnalysis x) - (SELECT MIN(y.Score) FROM FinalAnalysis y), 0), 2) AS ScorePercentile,
    CAST(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56') - fa.CreationDate) AS INTEGER) AS AgeInDays,
    CASE 
        WHEN fa.Score > 0 AND fa.AnswerCount > 0 THEN ROUND((100.0 * fa.AnswerCount) / (fa.Score + 1), 2)
        ELSE NULL
    END AS AnswerScoreRatio,
    CASE 
        WHEN fa.AnswerCount > 0 THEN (fa.Score / NULLIF(fa.AnswerCount, 0))
        ELSE NULL
    END AS ScorePerAnswer,
    CASE 
        WHEN fa.ViewCount > 0 THEN (fa.Score / NULLIF(fa.ViewCount, 0))
        ELSE NULL
    END AS ScorePerView
FROM FinalAnalysis fa
WHERE 
    (fa.Score > -50 OR fa.Score IS NULL) AND
    (fa.ViewCount > 0 OR fa.ViewCount IS NULL) AND
    (fa.OwnerUserId IS NOT NULL) AND
    (fa.PostId > 0) AND
    (fa.Score > (SELECT AVG(x.Score) FROM FinalAnalysis x) OR fa.Score IS NULL)
ORDER BY 
    fa.Score DESC,
    fa.ViewCount DESC,
    fa.CreationDate DESC
OFFSET 100 
LIMIT 5000;