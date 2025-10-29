WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LatestPostDate,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        COALESCE(AVG(p.Score), 0) AS AvgScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        UpVotes,
        DownVotes,
        PostCount,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        LatestPostDate,
        TotalScore,
        TotalViews,
        AvgScore,
        AllTags,
        DENSE_RANK() OVER (ORDER BY TotalScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY PostCount DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) AS BadgeRank
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementMetric,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS PostTypeDesc,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2015-01-01'
),
UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN ph.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) AS ModerationCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN ph.Id END) AS LockUnlockCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24, 25, 35, 36) THEN ph.Id END) AS OtherActivityCount,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.Count > 1000 THEN 'Popular' WHEN t.Count > 500 THEN 'Medium' ELSE 'Low' END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PrevCount,
        (t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC)) AS CountChange
    FROM Tags t
    WHERE t.Count > 100
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalScore,
    ru.PostCount,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.BadgeCount,
    ru.ScoreRank,
    ru.PostRank,
    ru.BadgeRank,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.CreationDate,
    pa.PostTypeDesc,
    pa.EngagementMetric,
    uas.EditCount,
    uas.ModerationCount,
    uas.LockUnlockCount,
    tp.TagName,
    tp.Count AS TagCount,
    tp.PopularityLevel,
    CASE WHEN (ru.Reputation * 10000 + ru.TotalScore) > (SELECT AVG(Reputation * 10000 + TotalScore) FROM RankedUsers) THEN 'AboveAverage' ELSE 'BelowAverage' END AS PerformanceTier,
    CASE WHEN ru.TotalScore > 10000 THEN 'HighlyActive' WHEN ru.TotalScore > 5000 THEN 'ModerateActive' ELSE 'LowActive' END AS ActivityLevel,
    ('User ' || ru.DisplayName || ' has ' || CAST(ru.PostCount AS varchar) || ' posts, ' ||
        'scored ' || CAST(ru.TotalScore AS varchar) || ' points, and ' ||
        'earned ' || CAST(ru.BadgeCount AS varchar) || ' badges') AS UserSummary,
    CASE 
        WHEN ru.TotalViews IS NULL THEN 'No Views Data' 
        WHEN ru.TotalViews > 100000 THEN 'High Traffic' 
        WHEN ru.TotalViews > 50000 THEN 'Medium Traffic' 
        ELSE 'Low Traffic' 
    END AS TrafficCategory,
    CASE 
        WHEN pa.Score >= 1000 AND pa.ViewCount >= 10000 THEN 'Trending'
        WHEN pa.Score >= 100 AND pa.ViewCount >= 1000 THEN 'Popular'
        WHEN pa.Score >= 10 AND pa.ViewCount >= 100 THEN 'Moderate'
        ELSE 'Regular'
    END AS PostCategory,
    ABS(pa.Score - COALESCE(pa.PrevScore, 0)) AS ScoreChange,
    ROUND((pa.Score * 1.0 / NULLIF(pa.ViewCount, 0)) * 100, 2) AS ScoreToViewRatio,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Votes v 
            WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2 AND v.UserId = ru.UserId
        ) THEN 'Upvoted'
        WHEN EXISTS (
            SELECT 1 FROM Votes v 
            WHERE v.PostId = pa.PostId AND v.VoteTypeId = 3 AND v.UserId = ru.UserId
        ) THEN 'Downvoted'
        ELSE 'NotVoted'
    END AS UserVoteStatus,
    CASE 
        WHEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) > 0 THEN 'Duplicate'
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = pa.PostId AND p.PostTypeId = 2) > 0 THEN 'Answer'
        ELSE 'Original'
    END AS PostStatus,
    NULLIF(
        CASE 
            WHEN tp.Count > 0 THEN (tp.Count * 100.0 / (SELECT SUM(t2.Count) FROM Tags t2)) 
            ELSE 0 
        END, 0
    ) AS TagPercentage,
    RANK() OVER (ORDER BY (ru.DisplayName || pa.Title) ASC) AS CombinedRank,
    CAST('2024-10-01 12:34:56' AS timestamp) - pa.CreationDate AS DaysSincePost,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId) AS CommentCountActual
FROM RankedUsers ru
INNER JOIN PostAnalysis pa ON ru.UserId = pa.OwnerUserId
LEFT JOIN UserActivitySummary uas ON ru.UserId = uas.UserId
LEFT JOIN TagPopularity tp ON pa.Tags LIKE ('%' || tp.TagName || '%')
WHERE 
    ru.ScoreRank <= 1000 AND 
    ru.PostRank <= 500 AND 
    ru.BadgeRank <= 200 AND 
    (pa.EngagementMetric > 10 OR pa.PostTypeDesc = 'Question') AND
    (COALESCE(uas.EditCount,0) > 0 OR COALESCE(uas.ModerationCount,0) > 0 OR COALESCE(uas.LockUnlockCount,0) > 0) AND
    tp.PopularityLevel IN ('Popular', 'Medium') AND
    (pa.Score >= 5 OR pa.ViewCount >= 100 OR pa.CommentCount >= 3) AND
    (ru.Reputation > 1000 OR ru.TotalScore > 5000 OR ru.BadgeCount > 10)
ORDER BY 
    ru.TotalScore DESC,
    pa.Score DESC,
    pa.ViewCount DESC
LIMIT 500 OFFSET 100;