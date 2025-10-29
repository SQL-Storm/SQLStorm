-- {"query": "7369.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2203} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0 
        END AS HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1
            ELSE 0 
        END AS IsClosed,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0)
            ELSE 0 
        END AS EngagementScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(100) OVER (ORDER BY p.Score DESC) AS ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
                COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 1.0 / 
                NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
            ELSE 0 
        END AS AnswerToQuestionRatio,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
                AVG(p.Score) * AVG(p.AnswerCount)
            ELSE 0 
        END AS QuestionProductivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        ISNULL(p.Title, 'No Title') AS SampleTitle,
        ISNULL(SUBSTRING(p.Body, 1, 200), 'No Body') AS SampleBody,
        CASE 
            WHEN t.Count > 500 THEN 'High'
            WHEN t.Count > 100 THEN 'Medium'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Very Low' 
        END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS CountDifferenceToNext
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) > 0
),
ComplexMetrics AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.HasAcceptedAnswer,
        ps.IsClosed,
        ps.EngagementScore,
        ps.PrevScore,
        ps.PostRank,
        ps.ScoreRank,
        ps.ScoreQuartile,
        CASE 
            WHEN ps.Score > 0 THEN 
                ((ps.Score - ISNULL(ps.PrevScore, 0)) * 1.0 / NULLIF(ps.Score, 0)) * 100
            ELSE 0 
        END AS ScoreChangePercent,
        CASE 
            WHEN ps.Score > 0 THEN 
                (ps.Score * 1.0 / NULLIF((ps.AnswerCount + 1), 0)) * (ps.ViewCount + 1)
            ELSE 0 
        END AS ScorePerAnswerViewMetric,
        DATEDIFF(day, ps.CreationDate, ps.LastActivityDate) AS DaysSinceCreation,
        CASE 
            WHEN ps.LastActivityDate > ps.CreationDate THEN 
                DATEDIFF(day, ps.CreationDate, ps.LastActivityDate)
            ELSE 0 
        END AS ActivityDuration,
        CASE 
            WHEN ps.HasAcceptedAnswer = 1 AND ps.Score > 5 THEN 'High Quality'
            WHEN ps.HasAcceptedAnswer = 1 AND ps.Score <= 5 THEN 'Good Quality'
            WHEN ps.HasAcceptedAnswer = 0 AND ps.Score > 5 THEN 'Potential Quality'
            ELSE 'Needs Attention' 
        END AS QualityCategory
    FROM PostStats ps
    WHERE ps.Score >= 0
)
SELECT TOP 1000
    cm.PostId,
    cm.PostTypeId,
    cm.Score,
    cm.ViewCount,
    cm.AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.CreationDate,
    cm.LastActivityDate,
    cm.OwnerUserId,
    cm.Title,
    cm.Tags,
    cm.HasAcceptedAnswer,
    cm.IsClosed,
    cm.EngagementScore,
    cm.PrevScore,
    cm.PostRank,
    cm.ScoreRank,
    cm.ScoreQuartile,
    cm.ScoreChangePercent,
    cm.ScorePerAnswerViewMetric,
    cm.DaysSinceCreation,
    cm.ActivityDuration,
    cm.QualityCategory,
    ua.QuestionCount,
    ua.AnswerCount AS UserAnswerCount,
    ua.CommentCount AS UserCommentCount,
    ua.BadgeCount,
    ua.Reputation,
    ua.AvgPostScore,
    ua.AnswerToQuestionRatio,
    ua.QuestionProductivityScore,
    ta.TagName,
    ta.Count AS TagCount,
    ta.PopularityLevel,
    ta.TagRank,
    CASE 
        WHEN cm.Score > 0 AND cm.ScoreQuartile <= 5 THEN 'Top 5%'
        WHEN cm.Score > 0 AND cm.ScoreQuartile <= 20 THEN 'Top 20%'
        WHEN cm.Score > 0 AND cm.ScoreQuartile <= 50 THEN 'Top 50%'
        ELSE 'Below Average' 
    END AS ScorePerformanceTier,
    CASE 
        WHEN cm.Score > 0 AND cm.ScoreRank <= 100 THEN 'Premium'
        WHEN cm.Score > 0 AND cm.ScoreRank <= 500 THEN 'High'
        WHEN cm.Score > 0 AND cm.ScoreRank <= 5000 THEN 'Medium'
        ELSE 'Low' 
    END AS RankCategory,
    CASE 
        WHEN cm.HasAcceptedAnswer = 1 AND cm.Score > 10 THEN 'Veteran Contributor'
        WHEN ua.AnswerCount > 50 AND cm.Score > 5 THEN 'Active Contributor'
        WHEN cm.Score > 15 THEN 'Exceptional Contributor'
        ELSE 'Regular Contributor' 
    END AS ContributorStatus,
    'Post Analysis - ' + 
    CASE 
        WHEN cm.PostTypeId = 1 THEN 'Question'
        WHEN cm.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END + ' - ' +
    cm.QualityCategory + ' - ' +
    CASE 
        WHEN cm.Score >= 100 THEN 'Legendary'
        WHEN cm.Score >= 50 THEN 'Expert'
        WHEN cm.Score >= 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ComplexPostIdentifier,
    ROW_NUMBER() OVER (ORDER BY cm.Score DESC, cm.ViewCount DESC) AS OverallRank,
    SUM(cm.Score) OVER (ORDER BY cm.Score DESC) AS CumulativeScore,
    AVG(cm.Score) OVER (ORDER BY cm.Score DESC ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS MovingAvgOfScore,
    COUNT(*) OVER () AS TotalPosts,
    CASE 
        WHEN cm.LastActivityDate >= DATEADD(day, -30, GETDATE()) THEN 'Recently Active'
        WHEN cm.LastActivityDate >= DATEADD(day, -90, GETDATE()) THEN 'Active Recently'
        ELSE 'Inactive'
    END AS ActivityStatus,
    CASE 
        WHEN cm.Tags IS NOT NULL AND LEN(cm.Tags) > 0 THEN 
            'Tags: ' + SUBSTRING(cm.Tags, 1, 200)
        ELSE 'No Tags'
    END AS ShortTagList,
    IIF(ua.QuestionCount > 0, 
        (cm.AnswerCount * 1.0 / NULLIF(ua.QuestionCount, 0)), 
        0) AS AnswerRate,
    CASE 
        WHEN cm.PostRank = 1 THEN 'Original Post'
        WHEN cm.PostRank <= 5 THEN 'Top 5 Posts'
        WHEN cm.PostRank <= 10 THEN 'Top 10 Posts'
        ELSE 'Other Posts'
    END AS PostChronologyCategory
FROM ComplexMetrics cm
INNER JOIN UserActivity ua ON cm.OwnerUserId = ua.UserId
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT value 
    FROM STRING_SPLIT(cm.Tags, '<>')
    WHERE value IS NOT NULL AND LEN(value) > 0
)
WHERE cm.Score > 0 AND cm.PostTypeId IN (1, 2)
ORDER BY cm.Score DESC, cm.ViewCount DESC, cm.LastActivityDate DESC;