WITH UserScores AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        STRING_AGG(DISTINCT CAST(p.PostTypeId AS VARCHAR), ', ') AS PostTypes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.TotalPostScore DESC, us.Reputation DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY us.QuestionCount DESC) AS QuestionRank
    FROM UserScores us
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) AS TaggedPosts,
        COALESCE((SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) AS AvgScorePerTag,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS TopUsers,
        STRING_AGG(DISTINCT CAST(p.PostTypeId AS VARCHAR), ', ') AS UsedPostTypes
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
        COALESCE(COUNT(DISTINCT v.Id), 0) AS VoteCount,
        COALESCE(COUNT(DISTINCT b.Id), 0) AS BadgeCount,
        COALESCE(COUNT(DISTINCT ph.Id), 0) AS PostHistoryCount,
        STRING_AGG(DISTINCT CAST(ph.PostHistoryTypeId AS VARCHAR), ', ') AS HistoryTypes,
        MAX(ph.CreationDate) AS LastActivity
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.CreationDate >= DATE '2008-01-01'
    GROUP BY u.Id, u.DisplayName
),
ComplexFilter AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPostScore,
        ru.PostCount,
        ru.AvgPostScore,
        ru.LatestPostDate,
        ru.PostTypes,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.ScoreRank,
        ru.QuestionRank,
        COALESCE(ua.CommentCount, 0) AS CommentCount,
        COALESCE(ua.VoteCount, 0) AS VoteCount,
        COALESCE(ua.BadgeCount, 0) AS BadgeCount,
        COALESCE(ua.PostHistoryCount, 0) AS PostHistoryCount
    FROM RankedUsers ru
    LEFT JOIN UserActivity ua ON ru.UserId = ua.UserId
    WHERE (ru.TotalPostScore > 5000 OR ru.Reputation > 10000)
      AND (ru.QuestionCount > 50 OR ru.AnswerCount > 200)
      AND (ru.PostCount > 10 OR ru.ScoreRank <= 50)
),
FinalAggregated AS (
    SELECT 
        cf.UserId,
        cf.DisplayName,
        cf.Reputation,
        cf.TotalPostScore,
        cf.PostCount,
        cf.AvgPostScore,
        cf.LatestPostDate,
        cf.PostTypes,
        cf.QuestionCount,
        cf.AnswerCount,
        cf.ScoreRank,
        cf.QuestionRank,
        cf.CommentCount,
        cf.VoteCount,
        cf.BadgeCount,
        cf.PostHistoryCount,
        CASE 
            WHEN cf.BadgeCount > 50 THEN 'Elite'
            WHEN cf.BadgeCount > 25 THEN 'Veteran'
            WHEN cf.BadgeCount > 10 THEN 'Active'
            ELSE 'Regular'
        END AS UserTier,
        CASE 
            WHEN cf.QuestionCount > 100 THEN 'Expert'
            WHEN cf.QuestionCount > 50 THEN 'Advanced'
            WHEN cf.QuestionCount > 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS QuestionLevel,
        CASE 
            WHEN cf.AnswerCount > 100 THEN 'Master'
            WHEN cf.AnswerCount > 50 THEN 'Expert'
            WHEN cf.AnswerCount > 10 THEN 'Competent'
            ELSE 'Novice'
        END AS AnswerLevel,
        COALESCE(ROUND(CAST(cf.VoteCount AS NUMERIC) / NULLIF(cf.PostCount, 0), 2), 0) AS VoteRatio,
        COALESCE(ROUND(CAST(cf.BadgeCount AS NUMERIC) / NULLIF(cf.Reputation, 0) * 100, 4), 0) AS BadgeEfficiency,
        ROUND((CAST(cf.AnswerCount AS NUMERIC) / NULLIF(cf.QuestionCount, 0)) * 100, 2) AS AnswerToQuestionRatio
    FROM ComplexFilter cf
),
TagAnalysis AS (
    SELECT 
        ts.TagName,
        ts.Count,
        ts.TaggedPosts,
        ts.AvgScorePerTag,
        ts.TopUsers,
        ts.UsedPostTypes,
        ROW_NUMBER() OVER (ORDER BY ts.TaggedPosts DESC) AS TagRank,
        AVG(ts.AvgScorePerTag) OVER (ORDER BY ts.TaggedPosts DESC ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS MovingAvgScore,
        LAG(ts.AvgScorePerTag, 1) OVER (ORDER BY ts.TaggedPosts DESC) AS PrevAvgScore,
        LEAD(ts.AvgScorePerTag, 1) OVER (ORDER BY ts.TaggedPosts DESC) AS NextAvgScore
    FROM TagStats ts
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.TotalPostScore,
    fa.PostCount,
    fa.AvgPostScore,
    fa.LatestPostDate,
    fa.PostTypes,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.ScoreRank,
    fa.QuestionRank,
    fa.CommentCount,
    fa.VoteCount,
    fa.BadgeCount,
    fa.PostHistoryCount,
    fa.UserTier,
    fa.QuestionLevel,
    fa.AnswerLevel,
    fa.VoteRatio,
    fa.BadgeEfficiency,
    fa.AnswerToQuestionRatio,
    (SELECT STRING_AGG(tag.TagName, ', ')
     FROM Tags tag 
     WHERE tag.Count > 500 
       AND EXISTS (
           SELECT 1 FROM Posts p WHERE p.Tags LIKE '%' || tag.TagName || '%' AND p.OwnerUserId = fa.UserId
       )
    ) AS PersonalTagList,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.Score > 100) AS HighScorePostCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.Score < 0) AS NegativeScorePostCount,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.Score > 0) AS PositiveScoreAverage,
    (SELECT COALESCE(MAX(p.Score), 0) FROM Posts p WHERE p.OwnerUserId = fa.UserId) AS MaxScore,
    (SELECT COALESCE(MIN(p.Score), 0) FROM Posts p WHERE p.OwnerUserId = fa.UserId) AS MinScore,
    STRING_AGG(DISTINCT ta.TagName, ', ') AS TopTagNames,
    STRING_AGG(DISTINCT ta.TagName, ', ') AS PopularTagOrder,
    MAX(ta.TaggedPosts) AS MaxTaggedPosts,
    MIN(ta.TaggedPosts) AS MinTaggedPosts,
    AVG(ta.TaggedPosts) AS AvgTaggedPosts,
    1000000 + (fa.ScoreRank * 1000) + (fa.QuestionRank * 100) + (fa.BadgeCount * 10) + (fa.PostHistoryCount * 5) AS PerformanceScore
FROM FinalAggregated fa
LEFT JOIN TagAnalysis ta ON ta.TagRank <= 10
GROUP BY 
    fa.UserId, fa.DisplayName, fa.Reputation, fa.TotalPostScore, fa.PostCount, fa.AvgPostScore, 
    fa.LatestPostDate, fa.PostTypes, fa.QuestionCount, fa.AnswerCount, fa.ScoreRank, fa.QuestionRank,
    fa.CommentCount, fa.VoteCount, fa.BadgeCount, fa.PostHistoryCount, fa.UserTier, fa.QuestionLevel,
    fa.AnswerLevel, fa.VoteRatio, fa.BadgeEfficiency, fa.AnswerToQuestionRatio
HAVING 
    (fa.QuestionCount > 5 OR fa.AnswerCount > 50) 
    AND (fa.TotalPostScore >= 1000 OR fa.Reputation >= 5000)
    AND CAST(fa.LatestPostDate AS DATE) >= DATE '2023-01-01'
ORDER BY 
    fa.TotalPostScore DESC,
    PerformanceScore DESC,
    fa.Reputation DESC
LIMIT 100;