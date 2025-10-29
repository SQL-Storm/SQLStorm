-- {"query": "7319.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2303} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(b.Date) AS LastBadgeDate,
        MAX(v.CreationDate) AS LastVoteDate,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') AS AllPostTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id))
            ELSE 0 
        END AS PostActivityPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTaggers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') AS TagList
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 2
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)) > 5
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'None'
        END AS ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Notable'
            ELSE 'Regular'
        END AS PopularityTier,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextViewCount,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS GlobalViewRank
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
QuestionStatsWithBadges AS (
    SELECT 
        qc.PostId,
        qc.Title,
        qc.Score,
        qc.ViewCount,
        qc.AnswerCount,
        qc.CommentCount,
        qc.OwnerUserId,
        qc.ScoreCategory,
        qc.PopularityTier,
        qb.BadgeCount AS UserBadgeCount,
        CASE 
            WHEN qc.Score > 50 AND qc.AnswerCount > 0 THEN 'Active'
            WHEN qc.Score > 20 OR qc.ViewCount > 200 THEN 'Engaged'
            ELSE 'Passive'
        END AS EngagementLevel,
        COALESCE(qc.AnswerCount, 0) * COALESCE(qc.ViewCount, 0) AS ActivityMetric,
        NULLIF(qc.AnswerCount, 0) / NULLIF(qc.ViewCount, 0) AS AnswerPerViewRatio,
        COALESCE(SUBSTRING(qc.Title, 1, 15), 'No Title') AS ShortTitle
    FROM PostComplexityAnalysis qc
    LEFT JOIN (
        SELECT 
            b.UserId,
            COUNT(b.Id) AS BadgeCount
        FROM Badges b
        GROUP BY b.UserId
    ) qb ON qc.OwnerUserId = qb.UserId
),
TagRelatedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TagPostRank,
        RANK() OVER (ORDER BY t.Count DESC) AS TagPopularityRank
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT 
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t ON TRUE
    JOIN Tags tg ON t.TagName = tg.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserPerformanceMatrix AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.VoteCount,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastBadgeDate,
        uas.LastVoteDate,
        uas.AvgPostScore,
        uas.PostActivityPercentile,
        CASE 
            WHEN uas.PostCount > 100 AND uas.BadgeCount > 20 THEN 'Elite'
            WHEN uas.PostCount > 50 AND uas.BadgeCount > 10 THEN 'Veteran'
            WHEN uas.PostCount > 10 AND uas.BadgeCount > 2 THEN 'Active'
            ELSE 'Regular'
        END AS UserLevel,
        CONCAT('Level:', 
            CASE 
                WHEN uas.PostCount > 100 THEN 'Elite'
                WHEN uas.PostCount > 50 THEN 'Veteran'
                WHEN uas.PostCount > 10 THEN 'Active'
                ELSE 'Regular'
            END,
            'Rep:', uas.Reputation) AS UserProfileSummary
    FROM UserActivityStats uas
),
CombinedAnalysis AS (
    SELECT 
        usm.UserId,
        usm.DisplayName,
        usm.Reputation,
        usm.UserLevel,
        usm.UserProfileSummary,
        CAST(NULLIF(usm.PostCount * usm.AvgPostScore, 0) AS FLOAT) / NULLIF(usm.VoteCount, 0) AS ScorePerVote,
        ROW_NUMBER() OVER (ORDER BY usm.Reputation DESC) AS RepRank,
        DENSE_RANK() OVER (ORDER BY usm.UserLevel, usm.Reputation DESC) AS UserLevelRank,
        PERCENT_RANK() OVER (ORDER BY usm.Reputation) AS RepPercentile,
        STRING_AGG(DISTINCT CASE WHEN qa.PostId IS NOT NULL THEN CONCAT(qa.Title, ' (Score:', qa.Score, ')') END, ' | ') OVER (PARTITION BY usm.UserId) AS UserQuestionSummary
    FROM UserPerformanceMatrix usm
    LEFT JOIN QuestionStatsWithBadges qa ON usm.UserId = qa.OwnerUserId
),
FinalAnalysis AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.UserLevel,
        ca.UserProfileSummary,
        ca.ScorePerVote,
        ca.RepRank,
        ca.UserLevelRank,
        ca.RepPercentile,
        ca.UserQuestionSummary,
        CASE 
            WHEN ca.RepRank <= 10 THEN 'Top 10'
            WHEN ca.RepRank <= 100 THEN 'Top 100' 
            WHEN ca.RepRank <= 1000 THEN 'Top 1000'
            ELSE 'All'
        END AS ReputationTier,
        COALESCE(
            CASE WHEN COUNT(ta.TagName) > 0 THEN 
                STRING_AGG(DISTINCT ta.TagName, ', ') 
            END, 
            'No Tag Focus'
        ) AS TagFocus,
        COALESCE(
            STRING_AGG(DISTINCT CASE WHEN ta.TagName IS NOT NULL THEN ta.TagName END, ', ') 
            FILTER (WHERE ta.TagName IS NOT NULL), 
            'None'
        ) AS TagsUsed,
        ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC, ca.PostCount DESC) AS OverallRank
    FROM CombinedAnalysis ca
    LEFT JOIN TagRelatedPosts ta ON ca.UserId = ta.PostId
    GROUP BY 
        ca.UserId, 
        ca.DisplayName, 
        ca.Reputation, 
        ca.UserLevel, 
        ca.UserProfileSummary,
        ca.ScorePerVote,
        ca.RepRank,
        ca.UserLevelRank,
        ca.RepPercentile,
        ca.UserQuestionSummary
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.UserLevel,
    fa.UserProfileSummary,
    fa.ScorePerVote,
    fa.RepRank,
    fa.UserLevelRank,
    fa.RepPercentile,
    fa.UserQuestionSummary,
    fa.ReputationTier,
    fa.TagFocus,
    fa.TagsUsed,
    fa.OverallRank,
    NULLIF(fa.RepRank, 0) * NULLIF(fa.UserLevelRank, 0) AS RankMetric,
    CASE 
        WHEN fa.RepRank <= 50 AND fa.UserLevel = 'Elite' THEN 'Highly Valued'
        WHEN fa.RepRank <= 100 THEN 'Contributor'
        ELSE 'Participant'
    END AS RecognitionLevel,
    CONCAT('Rep:', fa.Reputation, ' Level:', fa.UserLevel) AS ConciseProfile,
    COUNT(*) OVER () AS TotalUsers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions,
    STRING_AGG(DISTINCT CASE WHEN fa.UserQuestionSummary IS NOT NULL THEN fa.UserQuestionSummary END, ' | ') FILTER (WHERE fa.UserQuestionSummary IS NOT NULL AND LENGTH(fa.UserQuestionSummary) > 10) OVER () AS SampleUserQuestions
FROM FinalAnalysis fa
WHERE fa.Reputation > 1000 
    AND fa.UserQuestionSummary IS NOT NULL
    AND fa.RepRank <= 1000
ORDER BY fa.RepRank, fa.UserLevelRank
LIMIT 100;