-- {"query": "7440.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3042} 
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
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF('DAY', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Diamond'
            WHEN u.Reputation >= 5000 THEN 'Platinum'
            WHEN u.Reputation >= 1000 THEN 'Gold'
            WHEN u.Reputation >= 500 THEN 'Silver'
            WHEN u.Reputation >= 100 THEN 'Bronze'
            ELSE 'Copper'
        END as ReputationTier,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as TagActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        TotalViews,
        LastPostDate,
        AccountAgeDays,
        ReputationTier,
        TagActivity,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, PostCount DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, TotalViews DESC) as RankByPosts,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as ReputationRank
    FROM UserStats
),
UserPostActivity AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalScore,
        tu.TotalViews,
        tu.LastPostDate,
        tu.AccountAgeDays,
        tu.ReputationTier,
        CASE 
            WHEN tu.PostCount > 0 AND tu.QuestionCount > 0 THEN 
                (CAST(tu.AnswerCount AS FLOAT) / CAST(tu.QuestionCount AS FLOAT)) * 100
            ELSE 0.0
        END as AnswerToQuestionRatio,
        CASE 
            WHEN tu.TotalViews > 0 THEN
                (CAST(tu.TotalScore AS FLOAT) / CAST(tu.TotalViews AS FLOAT)) * 1000
            ELSE 0.0
        END as ScorePerThousandViews,
        LAG(tu.TotalViews, 1, 0) OVER (ORDER BY tu.LastPostDate) as PreviousViews,
        LAG(tu.TotalScore, 1, 0) OVER (ORDER BY tu.LastPostDate) as PreviousScore,
        COALESCE(ABS(tu.TotalViews - LAG(tu.TotalViews, 1, 0) OVER (ORDER BY tu.LastPostDate)), 0) as ViewsChange,
        COALESCE(ABS(tu.TotalScore - LAG(tu.TotalScore, 1, 0) OVER (ORDER BY tu.LastPostDate)), 0) as ScoreChange,
        ROW_NUMBER() OVER (PARTITION BY tu.ReputationTier ORDER BY tu.TotalScore DESC) as TierRank,
        NTILE(10) OVER (ORDER BY tu.TotalScore) as ScoreDecile
    FROM TopUsers tu
),
QualifiedPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.Tags,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'Popular'
            WHEN p.Score >= 10 THEN 'Moderate'
            WHEN p.Score >= 0 THEN 'Low'
            ELSE 'Negative'
        END as PopularityLevel,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) as DaysOld,
        COALESCE(p.ClosedDate, '1900-01-01') as ClosedDate,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END as IsClosed,
        COALESCE(p.CommunityOwnedDate, '1900-01-01') as CommunityOwnedDate,
        CASE 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
            ELSE 0
        END as IsCommunityOwned,
        p.ContentLicense,
        p.LastActivityDate,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) as TagList,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') as TagArray,
        CASE 
            WHEN POSITION('<' in p.Tags) > 0 AND POSITION('>' in p.Tags) > 0 THEN 
                LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '<', '')) - LENGTH(REPLACE(p.Tags, '>', '')) + 2
            ELSE 0
        END as TagCount,
        CASE 
            WHEN p.OwnerUserId IN (
                SELECT UserId FROM UserPostActivity 
                WHERE TotalScore > 5000 AND PostCount > 100
            ) THEN 'HighActivityUser'
            WHEN p.OwnerUserId IN (
                SELECT UserId FROM UserPostActivity 
                WHERE TotalScore > 1000 AND PostCount > 50
            ) THEN 'MediumActivityUser'
            ELSE 'LowActivityUser'
        END as UserActivityLevel
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score IS NOT NULL 
      AND p.CreationDate > '2020-01-01'
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
AdvancedAnalysis AS (
    SELECT 
        qa.PostId,
        qa.Title,
        qa.Score,
        qa.ViewCount,
        qa.CreationDate,
        qa.OwnerUserId,
        qa.OwnerDisplayName,
        qa.Tags,
        qa.AnswerCount,
        qa.CommentCount,
        qa.FavoriteCount,
        qa.PostType,
        qa.PopularityLevel,
        qa.DaysOld,
        qa.IsClosed,
        qa.IsCommunityOwned,
        qa.ContentLicense,
        qa.LastActivityDate,
        qa.TagList,
        qa.TagArray,
        qa.TagCount,
        qa.UserActivityLevel,
        ROW_NUMBER() OVER (PARTITION BY qa.OwnerUserId ORDER BY qa.Score DESC) as UserPostRank,
        RANK() OVER (ORDER BY qa.Score DESC) as GlobalRank,
        DENSE_RANK() OVER (ORDER BY qa.PostType, qa.Score DESC) as TypeScoreRank,
        PERCENT_RANK() OVER (ORDER BY qa.Score) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY qa.Score) as ScoreCumulativeDistribution,
        NTILE(5) OVER (ORDER BY qa.Score) as ScoreQuintile,
        AVG(qa.Score) OVER (PARTITION BY qa.PostType) as AvgScoreByType,
        AVG(qa.Score) OVER (ORDER BY qa.CreationDate ROWS BETWEEN 100 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        MAX(qa.Score) OVER (ORDER BY qa.CreationDate) as MaxScoreToDate,
        LEAD(qa.Score, 1) OVER (ORDER BY qa.Score DESC) as NextHigherScore,
        LAG(qa.Score, 1) OVER (ORDER BY qa.Score DESC) as PreviousScore,
        CASE 
            WHEN qa.Score > (
                SELECT AVG(Score) FROM Posts WHERE PostTypeId = qa.PostType 
            ) THEN 'AboveAverage'
            ELSE 'BelowAverage'
        END as ScoreComparison,
        CASE 
            WHEN qa.Score > (
                SELECT AVG(Score) FROM Posts 
                WHERE PostTypeId = qa.PostType 
                  AND CreationDate BETWEEN '2021-01-01' AND '2022-12-31'
            ) THEN 'Post2021Average'
            ELSE 'Pre2021Average'
        END as ScorePeriodComparison,
        CASE 
            WHEN qa.TagCount > 5 THEN 'ManyTags'
            WHEN qa.TagCount >= 2 THEN 'SomeTags' 
            ELSE 'FewTags'
        END as TagDensityLevel,
        CASE 
            WHEN qa.PostType = 'Question' AND qa.AnswerCount > 10 THEN 'HighlyAnswered'
            WHEN qa.PostType = 'Question' AND qa.AnswerCount > 5 THEN 'ModeratelyAnswered' 
            WHEN qa.PostType = 'Question' AND qa.AnswerCount > 0 THEN 'SomeAnswered'
            ELSE 'Unanswered'
        END as AnswerStatus,
        CASE 
            WHEN qa.TagArray IS NOT NULL AND ARRAY_LENGTH(qa.TagArray, 1) > 0 THEN 
                (SELECT COUNT(*) FROM UNNEST(qa.TagArray) t WHERE t LIKE '%sql%')
            ELSE 0
        END as SqlTagCount,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 
             WHERE p2.ParentId = qa.PostId AND p2.PostTypeId = 2), 
            0
        ) as AnswerCountOnParent,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c2 
             WHERE c2.PostId = qa.PostId), 
            0
        ) as CommentCountOnPost,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = qa.PostId AND v.VoteTypeId = 2), 
            0
        ) as UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = qa.PostId AND v.VoteTypeId = 3), 
            0
        ) as DownvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = qa.PostId AND v.VoteTypeId = 5), 
            0
        ) as BookmarkCount,
        qa.Score * (1.0 + COALESCE(qa.AnswerCount, 0) * 0.1) as AdjustedScore,
        (
            (CASE WHEN qa.AnswerCount > 0 THEN 1 ELSE 0 END) * 
            (CASE WHEN qa.CommentCount > 0 THEN 1 ELSE 0 END) * 
            (CASE WHEN qa.FavoriteCount > 0 THEN 1 ELSE 0 END) * 
            (CASE WHEN qa.ViewCount > 100 THEN 1 ELSE 0 END)
        ) as EngagementLevel
    FROM QualifiedPosts qa
)
SELECT 
    aa.PostId,
    aa.Title,
    aa.Score,
    aa.ViewCount,
    aa.CreationDate,
    aa.OwnerUserId,
    aa.OwnerDisplayName,
    aa.Tags,
    aa.AnswerCount,
    aa.CommentCount,
    aa.FavoriteCount,
    aa.PostType,
    aa.PopularityLevel,
    aa.DaysOld,
    aa.IsClosed,
    aa.IsCommunityOwned,
    aa.ContentLicense,
    aa.LastActivityDate,
    aa.TagList,
    aa.TagArray,
    aa.TagCount,
    aa.UserActivityLevel,
    aa.UserPostRank,
    aa.GlobalRank,
    aa.TypeScoreRank,
    aa.ScorePercentile,
    aa.ScoreCumulativeDistribution,
    aa.ScoreQuintile,
    aa.AvgScoreByType,
    aa.MovingAvgScore,
    aa.MaxScoreToDate,
    aa.NextHigherScore,
    aa.PreviousScore,
    aa.ScoreComparison,
    aa.ScorePeriodComparison,
    aa.TagDensityLevel,
    aa.AnswerStatus,
    aa.SqlTagCount,
    aa.AnswerCountOnParent,
    aa.CommentCountOnPost,
    aa.UpvoteCount,
    aa.DownvoteCount,
    aa.BookmarkCount,
    aa.AdjustedScore,
    aa.EngagementLevel,
    CASE 
        WHEN aa.AdjustedScore > 100 AND aa.EngagementLevel > 1 THEN 'HighlyEngaged'
        WHEN aa.AdjustedScore > 50 AND aa.EngagementLevel > 0 THEN 'ModeratelyEngaged'
        ELSE 'LowEngagement'
    END as EngagementCategory
FROM AdvancedAnalysis aa
WHERE aa.TagCount > 0
  AND aa.Score IS NOT NULL
  AND aa.Views IS NOT NULL
  AND (aa.PostType = 'Question' OR aa.PostType = 'Answer')
  AND aa.GlobalRank BETWEEN 1 AND 2000
  AND (
    aa.Score > (
      SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 
    ) * 0.5
    OR EXISTS (
      SELECT 1 FROM Posts p 
      WHERE p.OwnerUserId = aa.OwnerUserId 
        AND p.Score > 1000
    )
  )
  AND (
    (aa.Score > 0 AND aa.AnswerCount > 0) 
    OR (aa.Score > 50 AND aa.CommentCount >= 2)
    OR (aa.Score > 5 AND aa.ViewCount > 500)
  )
ORDER BY aa.Score DESC, aa.ViewCount DESC, aa.LastActivityDate DESC
LIMIT 1000;