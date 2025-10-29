-- {"query": "7406.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2725} 
WITH UserActivityCTE AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
RankedUsers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY TotalScore DESC, Reputation DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY LastPostDate DESC) as RecentActivity,
        DENSE_RANK() OVER (ORDER BY AccountId) as AccountGroup,
        NTILE(10) OVER (ORDER BY TotalScore) as ScoreDecile
    FROM UserActivityCTE
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScore,
        p.Score - AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as ScoreDeviation,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAverage'
            ELSE 'Average'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as CleanTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostStats AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Body,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.PostTypeId,
        tp.Tags,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.ParentId,
        tp.PrevScore,
        tp.NextScore,
        tp.AvgScore,
        tp.ScoreDeviation,
        tp.ScoreCategory,
        tp.CleanTags,
        CASE 
            WHEN tp.Score > 100 THEN 'HighlyVoted'
            WHEN tp.Score > 50 THEN 'ModeratelyVoted'
            WHEN tp.Score >= 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END as VoteStatus,
        EXTRACT(YEAR FROM tp.CreationDate) as PostYear,
        EXTRACT(MONTH FROM tp.CreationDate) as PostMonth,
        CASE 
            WHEN tp.AnswerCount IS NULL OR tp.AnswerCount = 0 THEN 'NoAnswers'
            WHEN tp.AnswerCount <= 3 THEN 'FewAnswers'
            WHEN tp.AnswerCount <= 10 THEN 'ModerateAnswers'
            ELSE 'ManyAnswers'
        END as AnswerCategory,
        ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.CreationDate DESC) as OwnerPostRank,
        COUNT(*) OVER (PARTITION BY tp.OwnerUserId) as TotalOwnerPosts,
        RANK() OVER (PARTITION BY tp.OwnerUserId, tp.PostTypeId ORDER BY tp.Score DESC) as OwnerPostTypeRank,
        CASE 
            WHEN tp.AnswerCount > 0 AND EXISTS (
                SELECT 1 FROM Posts ap 
                WHERE ap.ParentId = tp.PostId 
                AND ap.Score > 0 
                AND ap.OwnerUserId = tp.OwnerUserId
            ) THEN 1 
            ELSE 0 
        END as HasPositiveAnswer
    FROM TopPosts tp
),
UserPosts AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.Views,
        ru.UpVotes,
        ru.DownVotes,
        ru.AccountId,
        ru.PostCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalScore,
        ru.TotalViews,
        ru.LastPostDate,
        ru.LastCommentDate,
        ru.LastBadgeDate,
        ru.AllTags,
        ru.ScoreRank,
        ru.RecentActivity,
        ru.AccountGroup,
        ru.ScoreDecile,
        STRING_AGG(DISTINCT pp.Title, '; ') as UserPostTitles,
        STRING_AGG(DISTINCT pp.ScoreCategory, ', ') as ScoreCategories,
        STRING_AGG(DISTINCT pp.VoteStatus, ', ') as VoteStatuses,
        STRING_AGG(DISTINCT pp.AnswerCategory, ', ') as AnswerCategories,
        AVG(pp.Score) as AvgUserScore,
        MAX(pp.Score) as MaxUserScore,
        SUM(pp.AnswerCount) as TotalUserAnswers,
        SUM(pp.CommentCount) as TotalUserComments,
        STRING_AGG(DISTINCT pp.CleanTags, ', ') as UserTagList,
        COUNT(*) as UserPostCount,
        STRING_AGG(CASE WHEN pp.PostTypeId = 1 THEN pp.Title END, '; ') as UserQuestions,
        STRING_AGG(CASE WHEN pp.PostTypeId = 2 THEN pp.Title END, '; ') as UserAnswers
    FROM RankedUsers ru
    INNER JOIN PostStats pp ON ru.UserId = pp.OwnerUserId
    WHERE ru.UserId IS NOT NULL
    GROUP BY ru.UserId, ru.DisplayName, ru.Reputation, ru.Views, ru.UpVotes, ru.DownVotes, 
             ru.AccountId, ru.PostCount, ru.CommentCount, ru.BadgeCount, ru.QuestionCount, 
             ru.AnswerCount, ru.TotalScore, ru.TotalViews, ru.LastPostDate, ru.LastCommentDate, 
             ru.LastBadgeDate, ru.AllTags, ru.ScoreRank, ru.RecentActivity, ru.AccountGroup, 
             ru.ScoreDecile
),
QualifiedUsers AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.Views,
        up.UpVotes,
        up.DownVotes,
        up.AccountId,
        up.PostCount,
        up.CommentCount,
        up.BadgeCount,
        up.QuestionCount,
        up.AnswerCount,
        up.TotalScore,
        up.TotalViews,
        up.LastPostDate,
        up.LastCommentDate,
        up.LastBadgeDate,
        up.AllTags,
        up.ScoreRank,
        up.RecentActivity,
        up.AccountGroup,
        up.ScoreDecile,
        up.UserPostTitles,
        up.ScoreCategories,
        up.VoteStatuses,
        up.AnswerCategories,
        up.AvgUserScore,
        up.MaxUserScore,
        up.TotalUserAnswers,
        up.TotalUserComments,
        up.UserTagList,
        up.UserPostCount,
        up.UserQuestions,
        up.UserAnswers,
        CASE WHEN up.QuestionCount > 0 THEN (up.QuestionCount * 1.0 / up.PostCount) ELSE 0 END as QuestionPercentage,
        CASE WHEN up.AnswerCount > 0 THEN (up.AnswerCount * 1.0 / up.PostCount) ELSE 0 END as AnswerPercentage,
        CASE WHEN up.TotalUserAnswers > 0 THEN (up.TotalUserAnswers * 1.0 / up.QuestionCount) ELSE 0 END as AnswerRate,
        CASE WHEN up.TotalUserComments > 0 THEN (up.TotalUserComments * 1.0 / up.PostCount) ELSE 0 END as CommentRate,
        CASE WHEN up.BadgeCount > 0 THEN (up.BadgeCount * 1.0 / up.PostCount) ELSE 0 END as BadgeRate,
        ROW_NUMBER() OVER (ORDER BY up.TotalScore DESC, up.Reputation DESC) as OverallRank,
        CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.Score > 500) THEN 1 ELSE 0 END as HasHighScoringPost
    FROM UserPosts up
    WHERE up.PostCount > 50
      AND up.Reputation > 1000
      AND (up.QuestionCount > 0 OR up.AnswerCount > 0)
)
SELECT 
    ou.UserId,
    ou.DisplayName,
    ou.Reputation,
    ou.Views,
    ou.UpVotes,
    ou.DownVotes,
    ou.AccountId,
    ou.PostCount,
    ou.CommentCount,
    ou.BadgeCount,
    ou.QuestionCount,
    ou.AnswerCount,
    ou.TotalScore,
    ou.TotalViews,
    ou.LastPostDate,
    ou.LastCommentDate,
    ou.LastBadgeDate,
    ou.AllTags,
    ou.ScoreRank,
    ou.RecentActivity,
    ou.AccountGroup,
    ou.ScoreDecile,
    ou.UserPostTitles,
    ou.ScoreCategories,
    ou.VoteStatuses,
    ou.AnswerCategories,
    ou.AvgUserScore,
    ou.MaxUserScore,
    ou.TotalUserAnswers,
    ou.TotalUserComments,
    ou.UserTagList,
    ou.UserPostCount,
    ou.UserQuestions,
    ou.UserAnswers,
    ou.QuestionPercentage,
    ou.AnswerPercentage,
    ou.AnswerRate,
    ou.CommentRate,
    ou.BadgeRate,
    ou.OverallRank,
    ou.HasHighScoringPost,
    CASE 
        WHEN ou.ScoreDecile >= 9 THEN 'TopTier'
        WHEN ou.ScoreDecile >= 7 THEN 'HighTier'
        WHEN ou.ScoreDecile >= 5 THEN 'MediumTier'
        WHEN ou.ScoreDecile >= 3 THEN 'LowTier'
        ELSE 'BottomTier'
    END as PerformanceTier,
    CASE 
        WHEN ou.Reputation > 10000 THEN 'Expert'
        WHEN ou.Reputation > 5000 THEN 'Advanced'
        WHEN ou.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as RepLevel,
    CASE 
        WHEN ou.QuestionCount * 1.0 / ou.AnswerCount > 2 THEN 'QuestionHeavy'
        WHEN ou.AnswerCount * 1.0 / ou.QuestionCount > 2 THEN 'AnswerHeavy'
        ELSE 'Balanced'
    END as ContributionStyle,
    CASE 
        WHEN ou.HasHighScoringPost = 1 AND ou.QuestionCount > 10 THEN 'ActiveContributor'
        WHEN ou.HasHighScoringPost = 1 AND ou.QuestionCount <= 10 THEN 'TacticalContributor'
        WHEN ou.QuestionCount > 25 THEN 'RegularContributor'
        ELSE 'OccasionalContributor'
    END as ContributionType,
    CONCAT('User ', ou.UserId, ' - ', ou.DisplayName, ' (', ou.Reputation, ' rep)') as UserDescription,
    CASE 
        WHEN LENGTH(ou.UserTagList) > 200 THEN SUBSTRING(ou.UserTagList, 1, 200) || '...'
        ELSE ou.UserTagList 
    END as TagSummary
FROM QualifiedUsers ou
WHERE ou.UserId IN (
    SELECT UserId FROM (
        SELECT UserId, COUNT(*) as PostCount 
        FROM Posts 
        WHERE PostTypeId = 1
        GROUP BY UserId
    ) AS TopQuestionOwners
    WHERE PostCount > 50
) 
  AND EXISTS (
    SELECT 1 FROM Badges b 
    WHERE b.UserId = ou.UserId AND b.Name IN ('Good Question', 'Great Question', 'Great Answer') 
    OR b.Name LIKE '%Nice%'
  )
  AND (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.OwnerUserId = ou.UserId 
    AND p.CreationDate > '2020-01-01'
  ) > 0
ORDER BY ou.TotalScore DESC, ou.Reputation DESC, ou.OverallRank ASC
LIMIT 500;