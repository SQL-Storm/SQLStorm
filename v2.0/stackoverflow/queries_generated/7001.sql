-- {"query": "7001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2458} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvotesReceived,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostAnalytics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 1 THEN 'Question without Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostCategory,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, GETDATE())) as AgeInDays,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile,
        CASE 
            WHEN p.ViewCount > 1000 AND p.Score > 50 THEN 'High Impact'
            WHEN p.ViewCount > 500 AND p.Score > 25 THEN 'Medium Impact'
            WHEN p.ViewCount > 100 AND p.Score > 10 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END as ImpactCategory,
        COALESCE(
            (SELECT TOP 1 ph.Comment 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 
             AND ph.Comment LIKE '%[0-9]%' 
             ORDER BY ph.CreationDate DESC), 
            'Not Closed'
        ) as CloseReason,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
UserPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.UpvotesReceived,
        uas.DownvotesReceived,
        uas.PostRank,
        uas.ReputationRank,
        CASE 
            WHEN uas.TotalPosts > 100 AND uas.Reputation > 1000 THEN 'Veteran Contributor'
            WHEN uas.TotalPosts > 50 AND uas.Reputation > 500 THEN 'Experienced Contributor'
            WHEN uas.TotalPosts > 10 AND uas.Reputation > 100 THEN 'Active Contributor'
            ELSE 'New Contributor'
        END as ContributorTier,
        COALESCE(
            (SELECT MAX(pa.Score) 
             FROM PostAnalytics pa 
             WHERE pa.OwnerUserId = uas.UserId AND pa.PostCategory = 'Question with Answers'), 
            0
        ) as MaxQuestionScore,
        COALESCE(
            (SELECT AVG(pa.Score) 
             FROM PostAnalytics pa 
             WHERE pa.OwnerUserId = uas.UserId AND pa.PostCategory = 'Answer'), 
            0
        ) as AvgAnswerScore
    FROM UserActivityStats uas
    WHERE uas.TotalPosts > 0
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Huge Tag'
            WHEN t.Count > 500 THEN 'Large Tag'
            WHEN t.Count > 100 THEN 'Medium Tag'
            ELSE 'Small Tag'
        END as TagSizeCategory,
        STUFF((
            SELECT DISTINCT ',' + p.Title
            FROM Posts p
            WHERE p.Tags LIKE '%' + t.TagName + '%'
            AND p.PostTypeId = 1
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') as SampleQuestions
    FROM Tags t
    WHERE t.IsRequired = 0 AND t.IsModeratorOnly = 0
),
FinalScoreCalculation AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.TotalPosts,
        up.QuestionCount,
        up.AnswerCount,
        up.CommentCount,
        up.BadgeCount,
        up.UpvotesReceived,
        up.DownvotesReceived,
        up.PostRank,
        up.ReputationRank,
        up.ContributorTier,
        up.MaxQuestionScore,
        up.AvgAnswerScore,
        CASE 
            WHEN up.Reputation > 10000 THEN 100
            WHEN up.Reputation > 5000 THEN 80
            WHEN up.Reputation > 1000 THEN 60
            WHEN up.Reputation > 500 THEN 40
            ELSE 20
        END + 
        CASE 
            WHEN up.TotalPosts >= 500 THEN 50
            WHEN up.TotalPosts >= 250 THEN 40
            WHEN up.TotalPosts >= 100 THEN 30
            WHEN up.TotalPosts >= 50 THEN 20
            ELSE 10
        END +
        CASE 
            WHEN up.BadgeCount >= 50 THEN 30
            WHEN up.BadgeCount >= 25 THEN 20
            WHEN up.BadgeCount >= 10 THEN 10
            ELSE 5
        END as FinalScore,
        DENSE_RANK() OVER (ORDER BY (
            CASE 
                WHEN up.Reputation > 10000 THEN 100
                WHEN up.Reputation > 5000 THEN 80
                WHEN up.Reputation > 1000 THEN 60
                WHEN up.Reputation > 500 THEN 40
                ELSE 20
            END + 
            CASE 
                WHEN up.TotalPosts >= 500 THEN 50
                WHEN up.TotalPosts >= 250 THEN 40
                WHEN up.TotalPosts >= 100 THEN 30
                WHEN up.TotalPosts >= 50 THEN 20
                ELSE 10
            END +
            CASE 
                WHEN up.BadgeCount >= 50 THEN 30
                WHEN up.BadgeCount >= 25 THEN 20
                WHEN up.BadgeCount >= 10 THEN 10
                ELSE 5
            END
        ) DESC) as OverallRank,
        (SELECT COUNT(*) FROM UserPerformance) as TotalUsers
    FROM UserPerformance up
)
SELECT 
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.TotalPosts,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.CommentCount,
    fs.BadgeCount,
    fs.UpvotesReceived,
    fs.DownvotesReceived,
    fs.PostRank,
    fs.ReputationRank,
    fs.ContributorTier,
    fs.MaxQuestionScore,
    fs.AvgAnswerScore,
    fs.FinalScore,
    fs.OverallRank,
    fs.TotalUsers,
    fs.FinalScore * 100.0 / fs.TotalUsers as ScorePercentage,
    CASE 
        WHEN fs.OverallRank <= fs.TotalUsers * 0.05 THEN 'Top 5%'
        WHEN fs.OverallRank <= fs.TotalUsers * 0.1 THEN 'Top 10%'
        WHEN fs.OverallRank <= fs.TotalUsers * 0.25 THEN 'Top 25%'
        WHEN fs.OverallRank <= fs.TotalUsers * 0.5 THEN 'Top 50%'
        ELSE 'Above Average'
    END as PerformanceTier,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = fs.UserId 
     AND p.PostTypeId = 1 
     AND p.AnswerCount = 0) as UnansweredQuestions,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = fs.UserId 
     AND p.PostTypeId = 2 
     AND p.Score >= 10) as HighValueAnswers,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = fs.UserId 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
     AND ph.CreationDate >= DATEADD(MONTH, -3, GETDATE())) as RecentEdits,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = fs.UserId 
     AND v.VoteTypeId = 5 
     AND v.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as RecentBookmarks,
    COALESCE(
        (SELECT TOP 1 ta.TagName 
         FROM Posts p
         JOIN Tags ta ON p.Tags LIKE '%' + ta.TagName + '%'
         WHERE p.OwnerUserId = fs.UserId 
         AND p.PostTypeId = 1
         GROUP BY ta.TagName
         ORDER BY COUNT(*) DESC), 
        'No Tags'
    ) as MostActiveTag,
    (SELECT TOP 1 p.Title 
     FROM Posts p 
     WHERE p.OwnerUserId = fs.UserId 
     AND p.PostTypeId = 1 
     ORDER BY p.Score DESC) as HighestRatedQuestion,
    (SELECT TOP 1 pa.Title 
     FROM PostAnalytics pa 
     WHERE pa.OwnerUserId = fs.UserId 
     AND pa.PostCategory = 'Answer' 
     ORDER BY pa.Score DESC) as HighestRatedAnswer,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (
         SELECT Id FROM Posts WHERE OwnerUserId = fs.UserId AND PostTypeId = 1
     ) 
     AND pl.LinkTypeId = 3) as DuplicateLinksCreated
FROM FinalScoreCalculation fs
WHERE fs.TotalPosts >= 10 AND fs.Reputation >= 100
ORDER BY fs.FinalScore DESC, fs.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;