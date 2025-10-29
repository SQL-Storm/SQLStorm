-- {"query": "7519.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1727} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Regular'
            ELSE 'Newbie'
        END AS UserTier,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        TotalScore,
        TotalViews,
        UserTier,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY TotalViews DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS RepRank
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
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
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Hot'
            WHEN p.Score > 50 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END AS Popularity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousDate,
        DATEDIFF(DAY, LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), p.CreationDate) AS DaysSinceLastPost
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
ComplexPostFilter AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.PostType,
        pa.Popularity,
        pa.UserPostRank,
        pa.PreviousScore,
        pa.DaysSinceLastPost,
        CASE 
            WHEN pa.Score > 100 AND pa.ViewCount > 1000 THEN 'HighImpact'
            WHEN pa.Score > 50 AND pa.ViewCount > 500 THEN 'MediumImpact'
            WHEN pa.Score > 10 AND pa.ViewCount > 100 THEN 'LowImpact'
            ELSE 'Minimal'
        END AS ImpactLevel,
        CASE 
            WHEN pa.DaysSinceLastPost > 30 AND pa.DaysSinceLastPost IS NOT NULL THEN 'Inactive'
            WHEN pa.DaysSinceLastPost > 7 AND pa.DaysSinceLastPost IS NOT NULL THEN 'SemiActive'
            ELSE 'Active'
        END AS ActivityLevel
    FROM PostAnalysis pa
    WHERE pa.PostType IN ('Question', 'Answer')
),
UserPostSummary AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.TotalScore,
        tu.TotalViews,
        tu.UserTier,
        tu.ScoreRank,
        tu.ViewRank,
        tu.RepRank,
        STRING_AGG(
            CASE 
                WHEN cpa.PostId IS NOT NULL THEN CONCAT(cpa.Title, ' (', cpa.Popularity, ')')
                ELSE NULL
            END, 
            '; '
        ) AS RecentPosts,
        COUNT(cpa.PostId) AS ActivePostCount,
        AVG(cpa.Score) AS AvgScore,
        MAX(cpa.ViewCount) AS MaxViews,
        MIN(cpa.DaysSinceLastPost) AS MinDaysSincePost
    FROM TopUsers tu
    LEFT JOIN ComplexPostFilter cpa ON tu.UserId = (
        SELECT p.OwnerUserId 
        FROM Posts p 
        WHERE p.Id = cpa.PostId 
        LIMIT 1
    )
    GROUP BY 
        tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, tu.CommentCount, 
        tu.BadgeCount, tu.TotalScore, tu.TotalViews, tu.UserTier, tu.ScoreRank, 
        tu.ViewRank, tu.RepRank
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.PostCount,
    ups.CommentCount,
    ups.BadgeCount,
    ups.TotalScore,
    ups.TotalViews,
    ups.UserTier,
    ups.ScoreRank,
    ups.ViewRank,
    ups.RepRank,
    ups.RecentPosts,
    ups.ActivePostCount,
    ups.AvgScore,
    ups.MaxViews,
    ups.MinDaysSincePost,
    CASE 
        WHEN ups.ScoreRank <= 10 OR ups.RepRank <= 10 THEN 'TopPerformer'
        WHEN ups.ScoreRank <= 50 OR ups.RepRank <= 50 THEN 'HighPerformer'
        WHEN ups.ScoreRank <= 100 OR ups.RepRank <= 100 THEN 'MidPerformer'
        ELSE 'Regular'
    END AS PerformanceRank,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ups.UserId 
         AND p.Score > 100 
         AND p.PostTypeId = 1), 
        0
    ) AS HighScoringQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ups.UserId 
         AND p.Score > 50 
         AND p.PostTypeId = 2), 
        0
    ) AS HighScoringAnswers,
    CASE 
        WHEN ups.UserTier IN ('Elite', 'Veteran') AND ups.PostCount > 50 THEN 'ActiveContributor'
        WHEN ups.UserTier IN ('Elite', 'Veteran') AND ups.PostCount >= 10 THEN 'RegularContributor'
        WHEN ups.UserTier IN ('Regular', 'Newbie') AND ups.PostCount >= 20 THEN 'EngagedMember'
        ELSE 'CasualMember'
    END AS EngagementLevel,
    (ups.TotalScore + ups.TotalViews) * (ups.RepRank + ups.ScoreRank) AS PerformanceScore,
    CONCAT(
        'User ', ups.DisplayName, ' (', ups.Reputation, ') has ',
        ups.PostCount, ' posts with ',
        ups.CommentCount, ' comments and ', ups.BadgeCount, ' badges.'
    ) AS UserSummary
FROM UserPostSummary ups
WHERE ups.PostCount >= 5
  AND ups.TotalScore >= 100
  AND ups.TotalViews >= 1000
  AND ups.RepRank <= 50
ORDER BY ups.TotalScore DESC, ups.TotalViews DESC
LIMIT 100;