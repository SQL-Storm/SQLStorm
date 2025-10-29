-- {"query": "7160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1206} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalScore,
        AvgScore,
        LastPostDate,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC) as RankByPosts
    FROM UserPostStats
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) as BadgeCount,
        STRING_AGG(b.Name, ', ') as BadgeNames,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') as GoldBadges,
        STRING_AGG(CASE WHEN b.Class = 2 THEN b.Name ELSE NULL END, ', ') as SilverBadges,
        STRING_AGG(CASE WHEN b.Class = 3 THEN b.Name ELSE NULL END, ', ') as BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 0)
            ELSE 0 
        END as PositiveAnswers,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes' 
            ELSE 'No' 
        END as HasAcceptedAnswer,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
        CASE 
            WHEN p.Score > 10 THEN 'High'
            WHEN p.Score > 0 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as AnswererName,
        a.Body,
        CASE 
            WHEN a.Score >= 10 THEN 'Excellent'
            WHEN a.Score >= 5 THEN 'Good'
            WHEN a.Score >= 0 THEN 'Fair'
            ELSE 'Poor'
        END as QualityRating,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as RankWithinQuestion
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT STRING_AGG(p.Title, '; ') FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), '') as SampleQuestions,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as QuestionCount
    FROM Tags t
    WHERE t.Count > 100
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalUsers,
    COUNT(CASE WHEN tu.RankByScore <= 5 THEN 1 END) as Top5ScoredUsers,
    COUNT(CASE WHEN tu.RankByPosts <= 5 THEN 1 END) as Top5PostUsers,
    COUNT(CASE WHEN qa.ScoreCategory = 'High' THEN 1 END) as HighScoreQuestions,
    COUNT(CASE WHEN qa.HasAcceptedAnswer = 'Yes' THEN 1 END) as QuestionsWithAcceptedAnswer,
    COUNT(CASE WHEN aa.RankWithinQuestion = 1 THEN 1 END) as TopAnswers,
    COUNT(CASE WHEN ta.QuestionCount > 1000 THEN 1 END) as PopularTags,
    AVG(tu.TotalScore) as AvgUserScore,
    AVG(qa.Score) as AvgQuestionScore,
    AVG(aa.Score) as AvgAnswerScore,
    MAX(ta.QuestionCount) as MaxTagQuestions,
    STRING_AGG(DISTINCT ta.TagName, ', ') as PopularTagsList,
    STRING_AGG(DISTINCT tu.DisplayName, ', ') as TopUsersList,
    STRING_AGG(DISTINCT qa.Title, '; ') as SampleQuestions
FROM TopUsers tu
FULL OUTER JOIN QuestionAnalysis qa ON 1=1
FULL OUTER JOIN AnswerAnalysis aa ON 1=1
FULL OUTER JOIN TagAnalysis ta ON 1=1
WHERE tu.UserId IS NOT NULL OR qa.QuestionId IS NOT NULL OR aa.AnswerId IS NOT NULL OR ta.TagName IS NOT NULL