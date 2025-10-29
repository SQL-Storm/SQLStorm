-- {"query": "7628.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1942} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) AS TotalQuestionViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) AS TotalAnswerViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) AS RankByScore,
        RANK() OVER (ORDER BY TotalPosts DESC) AS RankByPosts,
        DENSE_RANK() OVER (ORDER BY Badges DESC) AS RankByBadges,
        NTILE(10) OVER (ORDER BY Reputation) AS RepDecile
    FROM UserStats
),
TopUsers AS (
    SELECT UserId, DisplayName, TotalPosts, TotalScore, Badges
    FROM RankedUsers
    WHERE RankByScore <= 100
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeCategory,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly Scored'
            WHEN p.Score >= 50 THEN 'Moderately Scored'
            WHEN p.Score >= 10 THEN 'Low Scored'
            ELSE 'Very Low Scored'
        END AS ScoreCategory,
        COALESCE(p.Tags, '') AS CleanTags,
        LEFT(p.Title, 50) AS ShortTitle,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) AS DaysSinceCreation
    FROM Posts p
    WHERE p.CreationDate >= DATEADD('YEAR', -2, CURRENT_TIMESTAMP)
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.TotalPosts,
        tu.TotalScore,
        tu.Badges,
        pa.PostId,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.PostTypeCategory,
        pa.ScoreCategory,
        pa.CleanTags,
        pa.ShortTitle,
        pa.DaysSinceCreation,
        CASE 
            WHEN pa.DaysSinceCreation < 30 THEN 'New'
            WHEN pa.DaysSinceCreation BETWEEN 30 AND 180 THEN 'Medium Age'
            ELSE 'Old'
        END AS PostAgeCategory
    FROM TopUsers tu
    LEFT JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
    WHERE pa.PostId IS NOT NULL
),
AggregatedResults AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(TotalPosts) AS TotalPosts,
        SUM(TotalScore) AS TotalScore,
        SUM(Badges) AS TotalBadges,
        COUNT(PostId) AS PostsAnalyzed,
        AVG(Score) AS AvgScore,
        MAX(Score) AS MaxScore,
        MIN(Score) AS MinScore,
        AVG(ViewCount) AS AvgViewCount,
        SUM(ViewCount) AS TotalViews,
        AVG(AnswerCount) AS AvgAnswers,
        AVG(CommentCount) AS AvgComments
    FROM CombinedData
    GROUP BY UserId, DisplayName
),
TopPosts AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.PostTypeCategory,
        ca.ScoreCategory,
        ca.PostAgeCategory,
        ROW_NUMBER() OVER (PARTITION BY ca.UserId ORDER BY ca.Score DESC) AS PostRank
    FROM CombinedData ca
),
UserDetails AS (
    SELECT 
        a.UserId,
        a.DisplayName,
        a.TotalPosts,
        a.TotalScore,
        a.TotalBadges,
        a.PostsAnalyzed,
        a.AvgScore,
        a.MaxScore,
        a.MinScore,
        a.AvgViewCount,
        a.TotalViews,
        a.AvgAnswers,
        a.AvgComments,
        COALESCE(tp.PostId, 0) AS TopPostId,
        COALESCE(tp.Title, 'N/A') AS TopPostTitle,
        COALESCE(tp.Score, 0) AS TopPostScore,
        COALESCE(tp.ViewCount, 0) AS TopPostViews
    FROM AggregatedResults a
    LEFT JOIN TopPosts tp ON a.UserId = tp.UserId AND tp.PostRank = 1
),
FinalAnalysis AS (
    SELECT 
        ud.UserId,
        ud.DisplayName,
        ud.TotalPosts,
        ud.TotalScore,
        ud.TotalBadges,
        ud.PostsAnalyzed,
        ud.AvgScore,
        ud.MaxScore,
        ud.MinScore,
        ud.AvgViewCount,
        ud.TotalViews,
        ud.AvgAnswers,
        ud.AvgComments,
        ud.TopPostId,
        ud.TopPostTitle,
        ud.TopPostScore,
        ud.TopPostViews,
        CASE 
            WHEN ud.TotalScore > 0 THEN (ud.TotalScore / (ud.TotalPosts + 1)) 
            ELSE 0 
        END AS ScorePerPost,
        CASE 
            WHEN ud.TotalViews > 0 THEN (ud.TotalViews / (ud.TotalPosts + 1)) 
            ELSE 0 
        END AS ViewsPerPost,
        CASE 
            WHEN ud.TotalBadges > 0 THEN (ud.TotalBadges / (ud.TotalPosts + 1)) 
            ELSE 0 
        END AS BadgesPerPost,
        ROW_NUMBER() OVER (ORDER BY ud.TotalScore DESC, ud.TotalViews DESC) AS OverallRank
    FROM UserDetails ud
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.TotalPosts,
    fa.TotalScore,
    fa.TotalBadges,
    fa.PostsAnalyzed,
    fa.AvgScore,
    fa.MaxScore,
    fa.MinScore,
    fa.AvgViewCount,
    fa.TotalViews,
    fa.AvgAnswers,
    fa.AvgComments,
    fa.TopPostId,
    fa.TopPostTitle,
    fa.TopPostScore,
    fa.TopPostViews,
    fa.ScorePerPost,
    fa.ViewsPerPost,
    fa.BadgesPerPost,
    fa.OverallRank,
    CASE 
        WHEN fa.ScorePerPost >= 10 THEN 'High Performing'
        WHEN fa.ScorePerPost >= 5 THEN 'Moderate Performing'
        WHEN fa.ScorePerPost >= 1 THEN 'Low Performing'
        ELSE 'Very Low Performing'
    END AS PerformanceTier,
    CASE 
        WHEN fa.TopPostScore >= 100 THEN 'Elite Post'
        WHEN fa.TopPostScore >= 50 THEN 'High Value Post'
        WHEN fa.TopPostScore >= 10 THEN 'Moderate Value Post'
        ELSE 'Low Value Post'
    END AS TopPostValue,
    CASE 
        WHEN fa.TotalBadges >= 10 THEN 'Badge Master'
        WHEN fa.TotalBadges >= 5 THEN 'Badge Enthusiast'
        WHEN fa.TotalBadges >= 1 THEN 'Active Participant'
        ELSE 'Beginner'
    END AS BadgeStatus,
    CASE 
        WHEN fa.OverallRank BETWEEN 1 AND 10 THEN 'Top 10'
        WHEN fa.OverallRank BETWEEN 11 AND 50 THEN 'Top 50'
        WHEN fa.OverallRank BETWEEN 51 AND 100 THEN 'Top 100'
        ELSE 'Beyond Top 100'
    END AS RankCategory
FROM FinalAnalysis fa
WHERE fa.TotalPosts > 0
    AND fa.TotalScore >= 0
    AND (fa.TopPostScore >= 1 OR fa.TopPostScore IS NULL)
ORDER BY fa.OverallRank ASC
LIMIT 500;