-- {"query": "7488.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2353} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) as RankByPostCount,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as ReputationRank,
        NTILE(10) OVER (ORDER BY Reputation DESC) as ReputationQuartile
    FROM UserActivityStats
),
UserPostAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.QuestionsCount,
        tu.AnswersCount,
        tu.TotalQuestionScore,
        tu.TotalAnswerScore,
        CASE 
            WHEN tu.PostCount > 0 THEN CAST(tu.TotalAnswerScore AS FLOAT) / CAST(tu.PostCount AS FLOAT)
            ELSE 0 
        END as AvgScorePerPost,
        CASE 
            WHEN tu.QuestionCount > 0 THEN CAST(tu.TotalQuestionScore AS FLOAT) / CAST(tu.QuestionCount AS FLOAT)
            ELSE 0 
        END as AvgQuestionScore,
        CASE 
            WHEN tu.AnswerCount > 0 THEN CAST(tu.TotalAnswerScore AS FLOAT) / CAST(tu.AnswerCount AS FLOAT)
            ELSE 0 
        END as AvgAnswerScore,
        CASE 
            WHEN tu.Reputation >= 10000 THEN 'Elite'
            WHEN tu.Reputation >= 5000 THEN 'Master'
            WHEN tu.Reputation >= 1000 THEN 'Expert'
            WHEN tu.Reputation >= 500 THEN 'Novice'
            ELSE 'Newbie'
        END as ReputationTier,
        CASE 
            WHEN tu.BadgeCount > 10 THEN 'Active'
            WHEN tu.BadgeCount > 5 THEN 'Regular'
            WHEN tu.BadgeCount > 0 THEN 'Beginner'
            ELSE 'Inactive'
        END as ActivityLevel
    FROM TopUsers tu
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.Count * 1.0 / (SELECT MAX(Count) FROM Tags) as TagPopularityRatio,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        AVG(t.Count) OVER () as AvgTagCount,
        COUNT(*) OVER () as TotalTags
    FROM Tags t
),
PostAnalytics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END as PostType,
        CASE 
            WHEN p.ViewCount IS NULL OR p.ViewCount = 0 THEN 0
            WHEN p.Score IS NULL OR p.Score = 0 THEN 1
            ELSE CASE 
                WHEN p.ViewCount >= 1000 THEN 4
                WHEN p.ViewCount >= 500 THEN 3
                WHEN p.ViewCount >= 100 THEN 2
                ELSE 1
            END
        END as ViewPopularityRating,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            WHEN p.Score >= 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreTier,
        CASE 
            WHEN p.CommentCount >= 10 THEN 'High Activity'
            WHEN p.CommentCount >= 5 THEN 'Medium Activity'
            WHEN p.CommentCount >= 1 THEN 'Low Activity'
            ELSE 'No Comments'
        END as CommentActivity,
        DATEDIFF(day, p.CreationDate, GETDATE()) as AgeInDays,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.Score >= -5
      AND p.CreationDate >= DATEADD(year, -2, GETDATE())
),
PostTagAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostType,
        pa.ViewPopularityRating,
        pa.ScoreTier,
        pa.CommentActivity,
        pa.AgeInDays,
        pa.Tags,
        pa.AcceptedAnswerId,
        pa.ParentId,
        STRING_SPLIT(pa.Tags, '>') as TagSplit,
        CASE 
            WHEN pa.Tags IS NOT NULL AND pa.Tags != '' THEN 
                (SELECT COUNT(*) FROM STRING_SPLIT(pa.Tags, '>') WHERE value != '')
            ELSE 0
        END as TagCount,
        NULLIF(pa.Score + pa.ViewCount + pa.AnswerCount * 5 + pa.CommentCount * 2, 0) as CompositeScore,
        MAX(pa.Score) OVER (PARTITION BY pa.OwnerUserId) as MaxScorePerUser,
        AVG(pa.Score) OVER (PARTITION BY pa.OwnerUserId) as AvgScorePerUser
    FROM PostAnalytics pa
),
ComplexQueryResults AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.PostCount,
        upa.CommentCount,
        upa.BadgeCount,
        upa.QuestionsCount,
        upa.AnswersCount,
        upa.TotalQuestionScore,
        upa.TotalAnswerScore,
        upa.AvgScorePerPost,
        upa.AvgQuestionScore,
        upa.AvgAnswerScore,
        upa.ReputationTier,
        upa.ActivityLevel,
        MAX(CASE WHEN pt.TagCount > 0 THEN pt.TagCount ELSE 0 END) as MaxTagsInPost,
        AVG(CASE WHEN pt.TagCount > 0 THEN pt.TagCount ELSE 0 END) as AvgTagsPerPost,
        STRING_AGG(DISTINCT CASE 
            WHEN pt.TagCount > 0 THEN 
                (SELECT STRING_AGG(value, ', ') FROM STRING_SPLIT(pt.Tags, '>') WHERE value != '') 
            ELSE NULL 
        END, ', ') as AllPostTags,
        COUNT(*) as TotalPosts,
        COUNT(CASE WHEN pt.ScoreTier = 'High' THEN 1 END) as HighScorePosts,
        COUNT(CASE WHEN pt.CommentActivity = 'High Activity' THEN 1 END) as HighActivityPosts,
        COUNT(CASE WHEN pt.ViewPopularityRating = 4 THEN 1 END) as VeryPopularPosts,
        COUNT(CASE WHEN pt.AgeInDays <= 30 THEN 1 END) as RecentPosts,
        COUNT(CASE WHEN pt.AcceptedAnswerId IS NOT NULL THEN 1 END) as QuestionsWithAcceptedAnswer,
        AVG(pt.AgeInDays) as AvgAgeDays,
        AVG(pt.Score) as AvgPostScore,
        MAX(pt.Score) as MaxPostScore,
        MIN(pt.Score) as MinPostScore,
        STDEV(pt.Score) as StdDevScore
    FROM UserPostAnalysis upa
    LEFT JOIN PostTagAnalysis pt ON upa.UserId = pt.OwnerUserId
    GROUP BY 
        upa.UserId, upa.DisplayName, upa.Reputation, upa.PostCount, upa.CommentCount, 
        upa.BadgeCount, upa.QuestionsCount, upa.AnswersCount, upa.TotalQuestionScore, 
        upa.TotalAnswerScore, upa.AvgScorePerPost, upa.AvgQuestionScore, upa.AvgAnswerScore, 
        upa.ReputationTier, upa.ActivityLevel
)
SELECT 
    *,
    CASE 
        WHEN RepQuartile = 1 THEN 'Top 10%'
        WHEN RepQuartile = 2 THEN 'Next 20%'
        WHEN RepQuartile = 3 THEN 'Next 20%'
        WHEN RepQuartile = 4 THEN 'Bottom 10%'
        ELSE 'Other'
    END as ReputationTierLabel
FROM (
    SELECT 
        cq.*,
        NTILE(4) OVER (ORDER BY Reputation DESC) as RepQuartile,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) as OverallRank,
        PERCENT_RANK() OVER (ORDER BY Reputation DESC) as RepPercentile,
        RANK() OVER (ORDER BY AVGPostScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as PostRank,
        CASE 
            WHEN Reputation > 10000 AND (AvgAnswerScore >= 5 OR AvgQuestionScore >= 5) THEN 'High Performer'
            WHEN Reputation > 5000 AND (AvgAnswerScore >= 3 OR AvgQuestionScore >= 3) THEN 'Mid Performer'
            WHEN Reputation > 1000 AND (AvgAnswerScore >= 1 OR AvgQuestionScore >= 1) THEN 'Low Performer'
            ELSE 'Beginner'
        END as PerformanceLevel
    FROM ComplexQueryResults cq
) FinalResult
WHERE OverallRank <= 100
  AND (PostCount > 10 OR BadgeCount > 5 OR CommentCount > 20)
ORDER BY Reputation DESC, PostCount DESC, OverallRank ASC
OPTION (MAXDOP 8, RECOMPILE);