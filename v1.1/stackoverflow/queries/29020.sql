WITH UserActivityStats AS (
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.TotalViews,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY uas.TotalScore DESC, uas.Reputation DESC) AS RankByScore,
        DENSE_RANK() OVER (ORDER BY uas.BadgeCount DESC) AS RankByBadges,
        NTILE(100) OVER (ORDER BY uas.TotalViews DESC) AS PercentileByViews
    FROM UserActivityStats uas
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) AS RecentRank,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'QuestionWithAcceptedAnswer'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL AND p.AnswerCount > 0 THEN 'QuestionWithAnswers'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'QuestionNoAnswers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory
    FROM Posts p
    WHERE p.Score > 0 OR p.ViewCount > 1000 OR p.CommentCount > 5
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'HighInterestTag'
            WHEN t.Count > 100 THEN 'MediumInterestTag'
            WHEN t.Count > 10 THEN 'LowInterestTag'
            ELSE 'VeryLowInterestTag'
        END AS TagInterestLevel,
        COUNT(DISTINCT p.Id) AS PostsUsingTag,
        AVG(p.Score) AS AvgScoreOfTagPosts,
        STRING_AGG(DISTINCT CAST(p.OwnerUserId AS VARCHAR), ', ') AS UsersWhoUsedTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserPostAnalytics AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalScore,
        ru.TotalViews,
        ru.RankByScore,
        ru.RankByBadges,
        ru.PercentileByViews,
        ru.BadgeCount,
        CASE 
            WHEN ru.PostCount > 100 THEN 'HighlyActiveUser'
            WHEN ru.PostCount > 50 THEN 'ActiveUser'
            WHEN ru.PostCount > 10 THEN 'RegularUser'
            ELSE 'OccasionalUser'
        END AS UserActivityLevel,
        CASE 
            WHEN ru.Reputation > 100000 THEN 'LegendaryReputation'
            WHEN ru.Reputation > 10000 THEN 'MasterReputation'
            WHEN ru.Reputation > 1000 THEN 'ExpertReputation'
            ELSE 'BeginnerReputation'
        END AS ReputationLevel,
        (ru.TotalScore * 100.0 / NULLIF(ru.TotalViews, 0)) AS ScoreToViewRatio
    FROM RankedUsers ru
    WHERE ru.PostCount > 0
),
CombinedAnalysis AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.BadgeCount,
        upa.PostCount,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.TotalScore,
        upa.TotalViews,
        upa.RankByScore,
        upa.RankByBadges,
        upa.PercentileByViews,
        upa.UserActivityLevel,
        upa.ReputationLevel,
        upa.ScoreToViewRatio,
        tp.PostId,
        tp.Title,
        tp.Body,
        tp.Score AS PostScore,
        tp.ViewCount AS PostViewCount,
        tp.CreationDate AS PostCreationDate,
        tp.PostTypeId,
        tp.Tags,
        tp.PostCategory,
        ta.TagName,
        ta.Count AS TagCount,
        ta.TagInterestLevel
    FROM UserPostAnalytics upa
    LEFT JOIN TopPosts tp ON upa.UserId = tp.OwnerUserId
    LEFT JOIN TagAnalysis ta ON tp.Tags LIKE '%' || ta.TagName || '%'
    WHERE (tp.ScoreRank IS NOT NULL AND tp.ScoreRank <= 10) OR (tp.ViewRank IS NOT NULL AND tp.ViewRank <= 10)
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.TotalScore,
    ca.TotalViews,
    ca.RankByScore,
    ca.RankByBadges,
    ca.PercentileByViews,
    ca.UserActivityLevel,
    ca.ReputationLevel,
    ca.ScoreToViewRatio,
    ca.PostId,
    ca.Title,
    ca.PostScore,
    ca.PostViewCount,
    ca.PostCreationDate,
    ca.PostTypeId,
    ca.Tags,
    ca.PostCategory,
    ca.TagName,
    ca.TagCount,
    ca.TagInterestLevel,
    CASE 
        WHEN ca.TagInterestLevel = 'HighInterestTag' THEN 'Popular Topic'
        WHEN ca.TagInterestLevel = 'MediumInterestTag' THEN 'Moderate Topic'
        WHEN ca.TagInterestLevel = 'LowInterestTag' THEN 'Niche Topic'
        WHEN ca.TagInterestLevel = 'VeryLowInterestTag' THEN 'Rare Topic'
        ELSE 'Unknown Topic'
    END AS TopicPopularity,
    DENSE_RANK() OVER (ORDER BY ca.TotalScore DESC) AS GlobalScoreRank,
    PERCENT_RANK() OVER (ORDER BY ca.TotalViews DESC) AS ViewPercentile,
    CASE 
        WHEN (ca.ScoreToViewRatio > 0.01) THEN 'HighlyEngaged'
        WHEN (ca.ScoreToViewRatio > 0.001 AND ca.ScoreToViewRatio <= 0.01) THEN 'ModeratelyEngaged'
        WHEN (ca.ScoreToViewRatio <= 0.001) THEN 'LowEngagement'
        ELSE 'NoEngagement'
    END AS EngagementLevel,
    COALESCE(ca.Title, 'No Title') || ' - ' || COALESCE(ca.TagName, 'No Tag') AS PostTagSummary,
    (SELECT COUNT(*) FROM CombinedAnalysis ca2 WHERE ca2.UserId = ca.UserId AND ca2.PostTypeId = 1) AS QuestionCountForUser,
    (SELECT COUNT(*) FROM CombinedAnalysis ca3 WHERE ca3.UserId = ca.UserId AND ca3.PostTypeId = 2) AS AnswerCountForUser,
    CASE 
        WHEN ca.PostScore > 100 THEN 'HighlyVoted'
        WHEN ca.PostScore > 50 THEN 'ModeratelyVoted'
        WHEN ca.PostScore > 10 THEN 'LowVoted'
        ELSE 'NotVoted'
    END AS VoteLevel,
    CASE 
        WHEN ca.PostTypeId = 1 THEN 'Question'
        WHEN ca.PostTypeId = 2 THEN 'Answer'
        ELSE 'OtherPostType'
    END AS PostTypeDescription,
    COALESCE(ca.Body, 'No Content') AS PostContentPreview,
    CASE 
        WHEN ca.ReputationLevel = 'LegendaryReputation' AND ca.UserActivityLevel = 'HighlyActiveUser' THEN 'EliteContributor'
        WHEN ca.ReputationLevel = 'MasterReputation' AND ca.UserActivityLevel = 'ActiveUser' THEN 'ExperiencedContributor'
        WHEN ca.ReputationLevel = 'ExpertReputation' AND ca.UserActivityLevel = 'RegularUser' THEN 'RegularContributor'
        ELSE 'StandardContributor'
    END AS ContributorTier
FROM CombinedAnalysis ca
WHERE ca.Reputation > 0 
    AND (ca.PostCount > 0 OR ca.BadgeCount > 0)
    AND (ca.PostTypeId = 1 OR ca.PostTypeId = 2 OR ca.PostTypeId IS NULL)
ORDER BY 
    ca.RankByScore ASC,
    ca.TotalViews DESC,
    ca.ScoreToViewRatio DESC,
    ca.PostCreationDate DESC
LIMIT 1000;