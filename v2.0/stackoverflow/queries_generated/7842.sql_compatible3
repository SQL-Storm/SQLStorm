WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.ViewCount, 0) + COALESCE(p.Score, 0) + COALESCE(p.AnswerCount, 0) AS EngagementScore,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile,
        CASE 
            WHEN p.Score > 100 AND p.ViewCount > 1000 THEN 'High Impact'
            WHEN p.Score > 50 AND p.ViewCount > 500 THEN 'Medium Impact'
            WHEN p.Score > 10 OR p.ViewCount > 100 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END AS ImpactLevel,
        CAST( FLOOR(((EXTRACT(EPOCH FROM p.LastActivityDate) - EXTRACT(EPOCH FROM p.CreationDate)) / 86400.0)) AS INTEGER) AS DaysSinceLastActivity
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= TIMESTAMP '2020-01-01'
      AND (p.ViewCount > 0 OR p.Score > 0 OR p.AnswerCount > 0)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.PostId) as TotalPosts,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastActivity,
        AVG(ps.ViewCount) as AvgViews,
        SUM(ps.AnswerCount) as TotalAnswers,
        COUNT(DISTINCT ps.AcceptedAnswerId) as AcceptedAnswers,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier,
        CASE 
            WHEN u.Views > 10000 THEN 'Popular'
            WHEN u.Views > 1000 THEN 'Moderately Popular'
            ELSE 'Regular'
        END AS PopularityLevel
    FROM Users u
    LEFT JOIN PostStats ps ON ps.OwnerUserId = u.Id
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
      AND u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        DENSE_RANK() OVER (ORDER BY t.Count) as TagDensity,
        CASE 
            WHEN t.Count >= 1000 THEN 'Popular Tag'
            WHEN t.Count >= 100 THEN 'Moderate Tag'
            WHEN t.Count >= 10 THEN 'Niche Tag'
            ELSE 'Rare Tag'
        END AS TagPopularity,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as CountDifferenceFromNext
    FROM Tags t
    WHERE t.Count >= 10
),
PostWithTags AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.OwnerUserId,
        ps.PostTypeCategory,
        ps.EngagementScore AS EngagementScore,
        ps.ImpactLevel,
        ps.DaysSinceLastActivity,
        COALESCE(ua.DisplayName, 'Unknown') as OwnerDisplayName,
        ua.ReputationTier,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN
                SPLIT_PART(ps.Tags, '><', 1) 
            ELSE 'No Tags'
        END AS FirstTag,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN
                SPLIT_PART(ps.Tags, '><', (CHAR_LENGTH(ps.Tags) - CHAR_LENGTH(REPLACE(ps.Tags, '><', '')) )/ CHAR_LENGTH('><') + 1)
            ELSE 'No Tags'
        END AS LastTag,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN 
                CARDINALITY(STRING_TO_ARRAY(ps.Tags, '><'))
            ELSE 0
        END AS TagCount,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN 
                (SELECT STRING_AGG(DISTINCT tag, ', ') 
                 FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(ps.Tags FROM 2 FOR CHAR_LENGTH(ps.Tags)-2), '><')) AS t(tag)
                 WHERE LOWER(tag) LIKE '%java%' OR LOWER(tag) LIKE '%python%' OR LOWER(tag) LIKE '%javascript%'
                )
            ELSE NULL
        END AS TechnologyTagList
    FROM PostStats ps
    LEFT JOIN UserActivity ua ON ps.OwnerUserId = ua.UserId
),
ComplexMetrics AS (
    SELECT 
        pwt.PostId,
        pwt.Title,
        pwt.OwnerUserId,
        pwt.OwnerDisplayName,
        pwt.ReputationTier,
        pwt.Score,
        pwt.ViewCount,
        pwt.AnswerCount,
        pwt.CommentCount,
        pwt.PostTypeCategory,
        pwt.ImpactLevel,
        pwt.TagCount,
        pwt.FirstTag,
        pwt.LastTag,
        pwt.TechnologyTagList,
        pwt.EngagementScore,
        pwt.DaysSinceLastActivity,
        CASE 
            WHEN pwt.TagCount > 0 AND pwt.AnswerCount > 0 
            THEN ROUND(CAST(pwt.AnswerCount AS NUMERIC) / NULLIF(CAST(pwt.TagCount AS NUMERIC),0), 2)
            ELSE NULL
        END AS AnswerPerTagRatio,
        CASE 
            WHEN pwt.ViewCount > 0 
            THEN ROUND((CAST(pwt.Score AS NUMERIC) / NULLIF(CAST(pwt.ViewCount AS NUMERIC),0) * 100), 2)
            ELSE NULL
        END AS ScorePerViewRate,
        CASE 
            WHEN pwt.AnswerCount > 0 AND pwt.CommentCount > 0
            THEN ROUND(CAST(pwt.CommentCount AS NUMERIC) / NULLIF(CAST(pwt.AnswerCount AS NUMERIC),0), 2)
            ELSE NULL
        END AS CommentPerAnswerRatio,
        CASE 
            WHEN pwt.Score > 100 THEN 
                'High Engagement'
            WHEN pwt.Score > 50 THEN
                'Medium Engagement'
            ELSE 'Low Engagement'
        END AS EngagementCategory,
        CASE 
            WHEN pwt.DaysSinceLastActivity <= 7 THEN 'Recently Active'
            WHEN pwt.DaysSinceLastActivity <= 30 THEN 'Active'
            WHEN pwt.DaysSinceLastActivity <= 90 THEN 'Inactive'
            ELSE 'Very Inactive'
        END AS ActivityStatus,
        CASE 
            WHEN pwt.TagCount > 3 THEN 'Multi-Tagged'
            WHEN pwt.TagCount = 3 THEN 'Triple Tagged'
            WHEN pwt.TagCount = 2 THEN 'Double Tagged'
            WHEN pwt.TagCount = 1 THEN 'Single Tagged'
            ELSE 'Untagged'
        END AS TaggingStatus
    FROM PostWithTags pwt
    WHERE pwt.Score IS NOT NULL 
      AND pwt.ViewCount IS NOT NULL
),
AggregateMetrics AS (
    SELECT 
        cm.PostId,
        cm.Title,
        cm.OwnerUserId,
        cm.OwnerDisplayName,
        cm.ReputationTier,
        cm.Score,
        cm.ViewCount,
        cm.AnswerCount,
        cm.CommentCount,
        cm.PostTypeCategory,
        cm.ImpactLevel,
        cm.TagCount,
        cm.FirstTag,
        cm.LastTag,
        cm.TechnologyTagList,
        cm.EngagementScore,
        cm.DaysSinceLastActivity,
        cm.AnswerPerTagRatio,
        cm.ScorePerViewRate,
        cm.CommentPerAnswerRatio,
        cm.EngagementCategory,
        cm.ActivityStatus,
        cm.TaggingStatus,
        CASE 
            WHEN cm.AnswerPerTagRatio > 1 THEN TRUE
            ELSE FALSE
        END AS HighAnswerToTagRatio,
        CASE 
            WHEN cm.ScorePerViewRate > 5 THEN TRUE
            ELSE FALSE
        END AS HighQualityPost,
        CASE 
            WHEN cm.CommentPerAnswerRatio > 0.5 THEN TRUE
            ELSE FALSE
        END AS WellCommentedPost,
        CASE 
            WHEN cm.DaysSinceLastActivity <= 30 THEN TRUE
            ELSE FALSE
        END AS RecentlyActive,
        CASE 
            WHEN cm.ImpactLevel IN ('High Impact', 'Medium Impact') THEN 'Significant'
            ELSE 'Minor'
        END AS PostSignificance,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = cm.PostId 
               AND v.VoteTypeId IN (2, 3)
            ), 0
        ) AS TotalVotes,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = cm.PostId
            ), 0
        ) AS TotalComments,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostLinks pl 
             WHERE pl.PostId = cm.PostId 
               AND pl.LinkTypeId = 1
            ), 0
        ) AS LinkedPosts,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = cm.PostId 
               AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            ), 0
        ) AS EditHistoryCount,
        ROW_NUMBER() OVER (ORDER BY cm.Score DESC) as TopScoreRank,
        ROW_NUMBER() OVER (ORDER BY cm.ViewCount DESC) as TopViewRank,
        ROW_NUMBER() OVER (ORDER BY cm.AnswerCount DESC) as TopAnswerRank
    FROM ComplexMetrics cm
)
SELECT 
    am.PostId,
    am.Title,
    am.OwnerUserId,
    am.OwnerDisplayName,
    am.ReputationTier,
    am.Score,
    am.ViewCount,
    am.AnswerCount,
    am.CommentCount,
    am.PostTypeCategory,
    am.ImpactLevel,
    am.TagCount,
    am.FirstTag,
    am.LastTag,
    am.TechnologyTagList,
    am.EngagementScore,
    am.DaysSinceLastActivity,
    am.AnswerPerTagRatio,
    am.ScorePerViewRate,
    am.CommentPerAnswerRatio,
    am.EngagementCategory,
    am.ActivityStatus,
    am.TaggingStatus,
    am.HighAnswerToTagRatio,
    am.HighQualityPost,
    am.WellCommentedPost,
    am.RecentlyActive,
    am.PostSignificance,
    am.TotalVotes,
    am.TotalComments,
    am.LinkedPosts,
    am.EditHistoryCount,
    am.TopScoreRank,
    am.TopViewRank,
    am.TopAnswerRank,
    CASE 
        WHEN am.TopScoreRank <= 100 THEN 'Top 100 Score'
        WHEN am.TopScoreRank <= 500 THEN 'Top 500 Score'
        WHEN am.TopScoreRank <= 1000 THEN 'Top 1000 Score'
        ELSE 'Lower Rank'
    END AS ScoreRankCategory,
    CASE 
        WHEN am.TopViewRank <= 100 THEN 'Top 100 Views'
        WHEN am.TopViewRank <= 500 THEN 'Top 500 Views'
        WHEN am.TopViewRank <= 1000 THEN 'Top 1000 Views'
        ELSE 'Lower Views'
    END AS ViewRankCategory,
    CASE 
        WHEN am.TopAnswerRank <= 100 THEN 'Top 100 Answers'
        WHEN am.TopAnswerRank <= 500 THEN 'Top 500 Answers'
        WHEN am.TopAnswerRank <= 1000 THEN 'Top 1000 Answers'
        ELSE 'Lower Answers'
    END AS AnswerRankCategory
FROM AggregateMetrics am
WHERE am.Score > 0
  AND (
    am.HighAnswerToTagRatio = TRUE 
    OR am.HighQualityPost = TRUE 
    OR am.WellCommentedPost = TRUE
    OR am.RecentlyActive = TRUE
  )
ORDER BY am.Score DESC, am.ViewCount DESC, am.AnswerCount DESC
LIMIT 250;