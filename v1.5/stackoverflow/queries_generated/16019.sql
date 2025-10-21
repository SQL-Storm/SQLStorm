-- {"query": "16019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1877}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS LocationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01'
        AND (u.Reputation > 1000 OR u.UpVotes > 100)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        COALESCE(p.ViewCount, 0) * LOG(COALESCE(p.Score, 0) + 2) AS EngagementScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Unanswered'
        END AS PostStatus,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT STRING_AGG(DISTINCT b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = p.OwnerUserId AND b.Date <= p.CreationDate) AS UserBadgesAtPostTime,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostDate,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2019-01-01'
        AND (p.Body IS NOT NULL AND LENGTH(p.Body) > 100)
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
)
SELECT 
    uem.DisplayName,
    COALESCE(uem.Location, 'Unknown Location') AS UserLocation,
    uem.Reputation,
    uem.PostCount,
    uem.VoteCount,
    ROUND(uem.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    cpa.PostStatus,
    COUNT(DISTINCT cpa.PostId) AS PostsInCategory,
    AVG(cpa.EngagementScore) AS AvgEngagementScore,
    MAX(cpa.EditCount) AS MaxEdits,
    STRING_AGG(DISTINCT tp.TagName, '; ') FILTER (WHERE tp.AvgPostScore > 5) AS TopPerformingTags,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
     WHERE pl.PostId = cpa.PostId AND pl.LinkTypeId = 1) AS LinkedPostCount,
    CASE 
        WHEN uem.LocationRank <= 3 THEN 'Top Regional User'
        WHEN uem.PostCountRank <= 100 THEN 'Prolific Contributor'
        WHEN uem.AvgAnswerScore > 10 THEN 'Quality Answerer'
        ELSE 'Regular User'
    END AS UserTier,
    EXTRACT(EPOCH FROM (cpa.PrevPostDate - LAG(cpa.PrevPostDate) OVER (PARTITION BY uem.UserId ORDER BY cpa.PostId))) / 86400 AS DaysBetweenPosts
FROM UserEngagementMetrics uem
INNER JOIN ComplexPostAnalysis cpa ON EXISTS (
    SELECT 1 FROM Posts p WHERE p.OwnerUserId = uem.UserId AND p.Id = cpa.PostId
)
LEFT OUTER JOIN Posts p_tag ON p_tag.Id = cpa.PostId AND p_tag.Tags IS NOT NULL
LEFT OUTER JOIN TagPerformance tp ON p_tag.Tags LIKE '%<' || tp.TagName || '>%'
WHERE cpa.EngagementScore > 0
    AND (cpa.EditCount IS NULL OR cpa.EditCount < 20)
    AND uem.PostCountRank <= 1000
    AND NOT EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = cpa.PostId 
        AND v.VoteTypeId IN (4, 12) 
        HAVING COUNT(*) > 5
    )
GROUP BY 
    uem.UserId, uem.DisplayName, uem.Location, uem.Reputation, 
    uem.PostCount, uem.VoteCount, uem.AvgAnswerScore, 
    uem.LocationRank, uem.PostCountRank,
    cpa.PostStatus, cpa.PostId, cpa.EngagementScore, cpa.EditCount, cpa.PrevPostDate
HAVING COUNT(DISTINCT cpa.PostId) >= 1
ORDER BY 
    AvgEngagementScore DESC NULLS LAST,
    uem.Reputation DESC,
    PostsInCategory DESC
LIMIT 500;
