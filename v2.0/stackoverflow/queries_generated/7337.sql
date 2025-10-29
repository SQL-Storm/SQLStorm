-- {"query": "7337.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2444} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LatestPostDate,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByScore,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'VeryLowVoted'
        END as PopularityLevel
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
),
PostAnalysis AS (
    SELECT 
        q.PostId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        q.RankByScore,
        q.ScoreQuartile,
        q.PopularityLevel,
        CASE 
            WHEN q.AnswerCount = 0 THEN 'NoAnswers'
            WHEN q.AnswerCount = 1 THEN 'OneAnswer'
            WHEN q.AnswerCount BETWEEN 2 AND 5 THEN 'FewAnswers'
            WHEN q.AnswerCount BETWEEN 6 AND 10 THEN 'ManyAnswers'
            ELSE 'ExtremelyAnswered'
        END as AnswerQuantity,
        CASE 
            WHEN q.CommentCount = 0 THEN 'NoComments'
            WHEN q.CommentCount = 1 THEN 'OneComment'
            WHEN q.CommentCount BETWEEN 2 AND 5 THEN 'FewComments'
            WHEN q.CommentCount BETWEEN 6 AND 10 THEN 'ManyComments'
            ELSE 'ExtremelyCommented'
        END as CommentQuantity,
        LAG(q.Score, 1) OVER (ORDER BY q.Score DESC) as PreviousScore,
        LEAD(q.Score, 1) OVER (ORDER BY q.Score DESC) as NextScore,
        AVG(q.Score) OVER (ORDER BY q.Score DESC ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as MovingAverageScore
    FROM TopQuestions q
    WHERE q.RankByScore <= 5
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        ISNULL(t.IsRequired, 0) as IsRequiredTag,
        ISNULL(t.IsModeratorOnly, 0) as IsModeratorOnlyTag,
        CASE 
            WHEN t.Count > 1000 THEN 'VeryPopular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'ModeratelyPopular'
            ELSE 'LessPopular'
        END as PopularityCategory,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate as UserCreationDate,
        MAX(COALESCE(p.CreationDate, c.CreationDate)) as LastActivityDate,
        COALESCE(DATEDIFF(day, u.CreationDate, MAX(COALESCE(p.CreationDate, c.CreationDate))), 0) as DaysSinceCreation,
        DATEDIFF(day, u.CreationDate, GETDATE()) as TotalDaysAsMember,
        CASE 
            WHEN DATEDIFF(day, u.CreationDate, MAX(COALESCE(p.CreationDate, c.CreationDate))) > 365 THEN 'ActiveLongTerm'
            WHEN DATEDIFF(day, u.CreationDate, MAX(COALESCE(p.CreationDate, c.CreationDate))) > 90 THEN 'ActiveMediumTerm'
            WHEN DATEDIFF(day, u.CreationDate, MAX(COALESCE(p.CreationDate, c.CreationDate))) > 30 THEN 'ActiveShortTerm'
            ELSE 'Inactive'
        END as ActivityStatus,
        COUNT(DISTINCT p.Id) as PostsCreated,
        COUNT(DISTINCT c.Id) as CommentsMade,
        COUNT(DISTINCT b.Id) as BadgesEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate
),
ComplexQuery AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.TotalViews,
        us.LatestPostDate,
        us.ScoreRank,
        us.RepRank,
        pa.PostId,
        pa.Title,
        pa.Score as QuestionScore,
        pa.ViewCount as QuestionViewCount,
        pa.AnswerCount as QuestionAnswerCount,
        pa.CommentCount as QuestionCommentCount,
        pa.CreationDate as QuestionCreationDate,
        pa.Tags,
        pa.RankByScore,
        pa.ScoreQuartile,
        pa.PopularityLevel,
        pa.AnswerQuantity,
        pa.CommentQuantity,
        pa.PreviousScore,
        pa.NextScore,
        pa.MovingAverageScore,
        ta.TagName,
        ta.TagCount,
        ta.IsRequiredTag,
        ta.IsModeratorOnlyTag,
        ta.PopularityCategory,
        ta.TagRank,
        ua.LastActivityDate,
        ua.DaysSinceCreation,
        ua.TotalDaysAsMember,
        ua.ActivityStatus,
        ua.PostsCreated,
        ua.CommentsMade,
        ua.BadgesEarned,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.9 THEN 'NearAverage'
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.7 THEN 'BelowAverage'
            ELSE 'BelowStandard'
        END as QuestionPerformance,
        DENSE_RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as UserQuestionRank,
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC) as GlobalQuestionRank,
        CONCAT(
            'User: ', us.DisplayName, ' - Question: ', pa.Title, 
            ' - Votes: ', pa.Score, ' - Views: ', pa.ViewCount,
            ' - Tags: ', ISNULL(pa.Tags, 'None')
        ) as QuestionSummary,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name LIKE '%Nice%') THEN 'NiceBadgeHolder'
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name LIKE '%Good%') THEN 'GoodBadgeHolder'
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name LIKE '%Great%') THEN 'GreatBadgeHolder'
            ELSE 'RegularUser'
        END as UserBadgeTier,
        CASE 
            WHEN pa.AnswerCount > 0 THEN CAST(pa.AnswerCount AS FLOAT) / NULLIF(pa.ViewCount, 0) 
            ELSE NULL 
        END as AnswerToViewRatio,
        CASE 
            WHEN pa.CommentCount > 0 THEN CAST(pa.CommentCount AS FLOAT) / NULLIF(pa.ViewCount, 0) 
            ELSE NULL 
        END as CommentToViewRatio
    FROM UserStats us
    INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.Tags IS NOT NULL AND ta.TagName IN (
        SELECT value FROM STRING_SPLIT(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '<')
    )
    INNER JOIN UserActivity ua ON us.UserId = ua.UserId
    WHERE us.Reputation > 1000 
      AND pa.Score > 50
      AND (pa.AnswerCount > 2 OR pa.CommentCount > 5)
      AND EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = us.UserId 
          AND p.PostTypeId = 1 
          AND p.CreationDate > DATEADD(year, -1, GETDATE())
      )
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Views,
    UpVotes,
    DownVotes,
    PostCount,
    CommentCount,
    BadgeCount,
    QuestionCount,
    AnswerCount,
    TotalScore,
    TotalViews,
    LatestPostDate,
    ScoreRank,
    RepRank,
    PostId,
    Title,
    QuestionScore,
    QuestionViewCount,
    QuestionAnswerCount,
    QuestionCommentCount,
    QuestionCreationDate,
    Tags,
    RankByScore,
    ScoreQuartile,
    PopularityLevel,
    AnswerQuantity,
    CommentQuantity,
    PreviousScore,
    NextScore,
    MovingAverageScore,
    TagName,
    TagCount,
    IsRequiredTag,
    IsModeratorOnlyTag,
    PopularityCategory,
    TagRank,
    LastActivityDate,
    DaysSinceCreation,
    TotalDaysAsMember,
    ActivityStatus,
    PostsCreated,
    CommentsMade,
    BadgesEarned,
    QuestionPerformance,
    UserQuestionRank,
    GlobalQuestionRank,
    QuestionSummary,
    UserBadgeTier,
    AnswerToViewRatio,
    CommentToViewRatio
FROM ComplexQuery
WHERE UserBadgeTier IN ('NiceBadgeHolder', 'GoodBadgeHolder', 'GreatBadgeHolder')
  AND QuestionPerformance IN ('AboveAverage', 'NearAverage')
  AND AnswerToViewRatio IS NOT NULL
  AND (AnswerToViewRatio > 0.1 OR CommentToViewRatio > 0.2)
ORDER BY QuestionScore DESC, TotalScore DESC, TotalViews DESC
OFFSET 100 ROWS
FETCH NEXT 50 ROWS ONLY
OPTION (MAXDOP 4);