-- {"query": "7010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2596}
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LatestPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
        AVG(EXTRACT(EPOCH FROM v.CreationDate)) AS AvgVoteEpoch
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE v.CreationDate >= DATE '2015-01-01'
    GROUP BY u.Id, u.DisplayName
),
PostComplexity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
            ELSE CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '><', '')) + 1
        END AS TagCount,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreLevel,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'Highly Answered'
            WHEN p.AnswerCount > 5 THEN 'Moderately Answered'
            ELSE 'Low Answered'
        END AS AnswerLevel,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= DATE '2018-01-01'
      AND p.Score IS NOT NULL
),
UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Date >= DATE '2019-01-01'
    GROUP BY u.Id, u.DisplayName
),
CombinedAnalysis AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.Questions,
        ups.Answers,
        ups.TotalQuestionScore,
        ups.TotalAnswerScore,
        ups.LatestPostDate,
        ups.AllTags,
        ua.TotalVotes,
        ua.UpVotes,
        ua.DownVotes,
        ua.Favorites,
        TO_TIMESTAMP(ua.AvgVoteEpoch) AS AvgVoteDate,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.LastBadgeDate,
        ub.BadgeNames,
        tc.Id AS PostId,
        tc.Title,
        tc.Score AS PostScore,
        tc.ViewCount,
        tc.AnswerCount,
        tc.CommentCount,
        tc.CreationDate AS PostCreationDate,
        tc.TagCount,
        tc.ScoreLevel,
        tc.AnswerLevel,
        tc.UserPostRank,
        tc.PrevScore,
        tc.NextScore,
        CASE 
            WHEN tc.PrevScore IS NOT NULL AND tc.NextScore IS NOT NULL THEN 
                CASE 
                    WHEN (tc.NextScore - tc.PrevScore) > 10 THEN 'Rapidly Increasing'
                    WHEN (tc.NextScore - tc.PrevScore) < -10 THEN 'Rapidly Decreasing'
                    ELSE 'Stable'
                END
            ELSE 'No Comparison Data'
        END AS ScoreTrend,
        CASE 
            WHEN tc.ViewCount > 1000 AND tc.Score > 50 THEN 'Popular High Score'
            WHEN tc.ViewCount > 1000 AND tc.Score <= 50 THEN 'Popular Low Score'
            WHEN tc.ViewCount <= 1000 AND tc.Score > 50 THEN 'Less Popular High Score'
            ELSE 'Less Popular Low Score'
        END AS PopularityScoreCategory,
        CASE 
            WHEN tc.AnswerLevel = 'Highly Answered' AND tc.ScoreLevel = 'High' THEN 'Highly Answered High Score'
            WHEN tc.AnswerLevel = 'Highly Answered' AND tc.ScoreLevel = 'Medium' THEN 'Highly Answered Medium Score'
            WHEN tc.AnswerLevel = 'Moderately Answered' AND tc.ScoreLevel = 'High' THEN 'Moderately Answered High Score'
            ELSE 'Other'
        END AS AnswerScoreCategory,
        DENSE_RANK() OVER (ORDER BY tc.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY tc.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY tc.AnswerCount DESC) AS AnswerRank
    FROM UserPostStats ups
    INNER JOIN UserActivity ua ON ups.UserId = ua.UserId
    INNER JOIN UserBadges ub ON ups.UserId = ub.UserId
    INNER JOIN PostComplexity tc ON ups.UserId = tc.OwnerUserId
    WHERE ups.TotalPosts > 0 AND ua.TotalVotes > 0 AND ub.TotalBadges > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.TotalQuestionScore,
    ca.TotalAnswerScore,
    ca.LatestPostDate,
    ca.AllTags,
    ca.TotalVotes,
    ca.UpVotes,
    ca.DownVotes,
    ca.Favorites,
    ca.AvgVoteDate,
    ca.TotalBadges,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.LastBadgeDate,
    ca.BadgeNames,
    ca.PostId,
    ca.Title,
    ca.PostScore,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.PostCreationDate,
    ca.TagCount,
    ca.ScoreLevel,
    ca.AnswerLevel,
    ca.UserPostRank,
    ca.PrevScore,
    ca.NextScore,
    ca.ScoreTrend,
    ca.PopularityScoreCategory,
    ca.AnswerScoreCategory,
    ca.ScoreRank,
    ca.ViewRank,
    ca.AnswerRank,
    CASE 
        WHEN (SELECT COUNT(*) FROM CombinedAnalysis ca2 
              WHERE ca2.UserId = ca.UserId AND ca2.PostScore > ca.PostScore) > 0 THEN 'Active Poster'
        ELSE 'Inactive Poster'
    END AS PosterStatus,
    CASE 
        WHEN ca.Reputation > 10000 AND ca.TotalPosts > 100 THEN 'Elite User'
        WHEN ca.Reputation > 5000 AND ca.TotalPosts > 50 THEN 'Experienced User'
        WHEN ca.Reputation > 1000 AND ca.TotalPosts > 10 THEN 'Active User'
        ELSE 'Regular User'
    END AS UserCategory,
    CASE 
        WHEN (SELECT COUNT(*) FROM TopTags tt WHERE tt.TagRank <= 5) > 0 THEN 'Tag Expert'
        ELSE 'General User'
    END AS ExpertiseLevel,
    ABS(ca.PostScore - COALESCE((SELECT AVG(ca3.PostScore) FROM CombinedAnalysis ca3 WHERE ca3.UserId = ca.UserId), 0)) AS ScoreDeviation,
    ROUND((CASE WHEN ca.ScoreLevel = 'High' AND ca.AnswerLevel = 'Highly Answered' THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF((SELECT COUNT(*) FROM CombinedAnalysis ca4 WHERE ca4.UserId = ca.UserId), 0), 2) AS HighPerformanceRatio,
    CASE 
        WHEN ca.PostScore > 100 THEN 'Trending'
        WHEN ca.PostScore > 50 THEN 'Notable'
        WHEN ca.PostScore > 0 THEN 'Mild'
        ELSE 'Unpopular'
    END AS TrendingStatus,
    STRING_AGG(
        CASE 
            WHEN ca.ScoreTrend = 'Rapidly Increasing' THEN 'RI'
            WHEN ca.ScoreTrend = 'Rapidly Decreasing' THEN 'RD'
            WHEN ca.ScoreTrend = 'Stable' THEN 'S'
            ELSE 'NC'
        END, 
        '|' 
    ) AS ScoreTrendSummary,
    'User-' || ca.UserId || '-Post-' || ca.PostId AS UniqueIdentifier,
    NULLIF(EXTRACT(DAY FROM (ca.PostCreationDate - ca.LatestPostDate)), 0) AS DaysSinceLastPost
FROM CombinedAnalysis ca
GROUP BY 
    ca.UserId, ca.DisplayName, ca.Reputation, ca.TotalPosts, ca.Questions, ca.Answers,
    ca.TotalQuestionScore, ca.TotalAnswerScore, ca.LatestPostDate, ca.AllTags, ca.TotalVotes,
    ca.UpVotes, ca.DownVotes, ca.Favorites, ca.AvgVoteDate, ca.TotalBadges, ca.GoldBadges,
    ca.SilverBadges, ca.BronzeBadges, ca.LastBadgeDate, ca.BadgeNames, ca.PostId, ca.Title,
    ca.PostScore, ca.ViewCount, ca.AnswerCount, ca.CommentCount, ca.PostCreationDate,
    ca.TagCount, ca.ScoreLevel, ca.AnswerLevel, ca.UserPostRank, ca.PrevScore, ca.NextScore,
    ca.ScoreTrend, ca.PopularityScoreCategory, ca.AnswerScoreCategory, ca.ScoreRank,
    ca.ViewRank, ca.AnswerRank
HAVING 
    COUNT(*) > 0
    AND COUNT(DISTINCT ca.ScoreTrend) > 0
    AND (COUNT(CASE WHEN ca.ScoreTrend = 'Rapidly Increasing' THEN 1 END) > 0 
         OR COUNT(CASE WHEN ca.ScoreTrend = 'Rapidly Decreasing' THEN 1 END) > 0)
ORDER BY 
    ca.TotalPosts DESC, 
    ca.Reputation DESC, 
    ca.ScoreRank ASC,
    ca.ViewRank ASC,
    ca.AnswerRank ASC
LIMIT 500;