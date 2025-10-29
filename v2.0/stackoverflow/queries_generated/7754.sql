-- {"query": "7754.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1669} 
WITH UserStats AS (
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
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Badges,
        LastPostDate,
        AvgPostScore,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS RankByReputation,
        DENSE_RANK() OVER (ORDER BY Badges DESC) AS RankByBadges
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
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.AcceptedAnswerId IS NULL THEN 'Answered No Accept'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered With Accept'
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'Answer with Score'
            WHEN p.PostTypeId = 2 AND p.Score = 0 THEN 'Answer with No Score'
        END AS PostCategory,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN (
                SELECT COUNT(*) 
                FROM Posts sp 
                WHERE sp.ParentId = p.ParentId AND sp.PostTypeId = 2 AND sp.Score > 0
            )
            ELSE 0 
        END AS OtherAnswersAbove
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
UserPostActivity AS (
    SELECT 
        ua.UserId,
        ua.PostId,
        ua.PostCategory,
        ua.Score,
        ua.ViewCount,
        ua.AnswerCount,
        ua.CreationDate,
        DATEDIFF('day', ua.CreationDate, CURRENT_TIMESTAMP) AS DaysSincePost,
        RANK() OVER (PARTITION BY ua.UserId ORDER BY ua.CreationDate DESC) AS RecentPostRank,
        SUM(ua.Score) OVER (PARTITION BY ua.UserId ORDER BY ua.CreationDate ROWS UNBOUNDED PRECEDING) AS CumulativeScore,
        AVG(ua.Score) OVER (PARTITION BY ua.UserId) AS UserAvgScore,
        MAX(ua.AnswerCount) OVER (PARTITION BY ua.UserId) AS MaxAnswers,
        NTILE(4) OVER (ORDER BY ua.Score) AS ScoreQuartile
    FROM PostAnalysis ua
    WHERE ua.OwnerUserId IS NOT NULL
),
DetailedAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Badges,
        tu.LastPostDate,
        tu.AvgPostScore,
        tu.AllTags,
        tu.RankByReputation,
        tu.RankByBadges,
        upa.PostId,
        upa.PostCategory,
        upa.Score,
        upa.ViewCount,
        upa.AnswerCount,
        upa.CreationDate,
        upa.DaysSincePost,
        upa.RecentPostRank,
        upa.CumulativeScore,
        upa.UserAvgScore,
        upa.MaxAnswers,
        upa.ScoreQuartile,
        CASE 
            WHEN upa.RecentPostRank = 1 AND upa.Score > 0 THEN 'Recent High Value'
            WHEN upa.RecentPostRank <= 3 AND upa.UserAvgScore > 10 THEN 'Consistent Performer'
            ELSE 'Regular Performer'
        END AS PerformanceCategory,
        CASE 
            WHEN ABS(upa.Score - upa.UserAvgScore) > 5 THEN 'Above/Below Average'
            ELSE 'Normal Range'
        END AS ScoreDeviation
    FROM TopUsers tu
    INNER JOIN UserPostActivity upa ON tu.UserId = upa.UserId
    WHERE upa.PostCategory IN ('Answered With Accept', 'Answer with Score', 'Question')
)
SELECT 
    da.UserId,
    da.DisplayName,
    da.Reputation,
    da.TotalPosts,
    da.Questions,
    da.Answers,
    da.Badges,
    da.LastPostDate,
    da.AvgPostScore,
    da.AllTags,
    da.RankByReputation,
    da.RankByBadges,
    da.PostId,
    da.PostCategory,
    da.Score,
    da.ViewCount,
    da.AnswerCount,
    da.CreationDate,
    da.DaysSincePost,
    da.RecentPostRank,
    da.CumulativeScore,
    da.UserAvgScore,
    da.MaxAnswers,
    da.ScoreQuartile,
    da.PerformanceCategory,
    da.ScoreDeviation,
    CASE 
        WHEN da.Score > 100 AND da.ViewCount > 1000 THEN 'High Impact'
        WHEN da.Score > 10 AND da.AnswerCount > 3 THEN 'Quality Contributor'
        WHEN da.ScoreQuartile = 4 THEN 'Top Performer'
        ELSE 'Standard Contributor'
    END AS ContributionLevel,
    COALESCE(
        NULLIF(SUBSTRING(da.AllTags, 1, 50), ''), 
        CONCAT('No Tags (', da.PostId, ')')
    ) AS TagSummary,
    LTRIM(RTRIM(
        CASE 
            WHEN da.PostCategory = 'Answered With Accept' 
            THEN CONCAT(da.Title, ' - ', da.Score, ' score')
            ELSE CONCAT('Question: ', da.Title, ' - ', da.AnswerCount, ' answers')
        END
    )) AS PostSummary,
    CASE 
        WHEN da.UserAvgScore > 50 THEN 'Elite Contributor'
        WHEN da.UserAvgScore > 25 THEN 'Advanced Contributor'
        WHEN da.UserAvgScore > 10 THEN 'Intermediate Contributor'
        ELSE 'Beginner Contributor'
    END AS ContributorLevel,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = da.PostId AND c.Score > 0), 
        0
    ) AS PositiveComments,
    ROW_NUMBER() OVER (
        PARTITION BY da.UserId 
        ORDER BY da.Score DESC, da.CreationDate DESC
    ) AS PostRankingWithinUser,
    DENSE_RANK() OVER (
        ORDER BY da.Score DESC, da.AnswerCount DESC
    ) AS GlobalPostRanking
FROM DetailedAnalysis da
WHERE (
    da.RecentPostRank <= 5 
    OR da.Score > 100
    OR da.DaysSincePost < 30
)
ORDER BY 
    da.Reputation DESC,
    da.Score DESC,
    da.LastPostDate DESC;