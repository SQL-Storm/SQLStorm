-- {"query": "47031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 71114, "output_tokens": 62284} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT t.Id, t.TagName, t.Count,
           CAST(t.TagName AS VARCHAR(1000)) AS tag_path,
           1 AS level
    FROM Tags t
    WHERE t.Count > 10000
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count,
           CAST(th.tag_path || ' -> ' || t2.TagName AS VARCHAR(1000)),
           th.level + 1
    FROM Tags t2
    JOIN tag_hierarchy th ON th.level < 3
    JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    JOIN Posts p2 ON p2.Tags LIKE '%<' || t2.TagName || '>%' 
                  AND p1.Id = p2.ParentId
    WHERE t2.Count > 1000
),
user_expertise AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
           COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedAnswers,
           AVG(p.Score) AS AvgPostScore,
           SUM(p.ViewCount) AS TotalViews,
           COUNT(DISTINCT b.Name) AS UniqueBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
           DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > CURRENT_DATE - INTERVAL '5 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_engagement AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           COUNT(DISTINCT v.UserId) AS UniqueVoters,
           COUNT(DISTINCT ph.UserId) AS UniqueEditors,
           COUNT(DISTINCT c.UserId) AS UniqueCommenters,
           MAX(ph.CreationDate) - MIN(p.CreationDate) AS ActivePeriod,
           CASE 
               WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
               WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
               WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
               ELSE 'Open'
           END AS Status,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.Score) AS MedianCommentScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CURRENT_DATE - INTERVAL '3 years'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.FavoriteCount, p.ClosedDate, 
             p.CommunityOwnedDate, p.AcceptedAnswerId
),
temporal_patterns AS (
    SELECT DATE_TRUNC('month', p.CreationDate) AS Month,
           COUNT(*) AS PostCount,
           AVG(p.Score) AS AvgScore,
           SUM(p.ViewCount) AS TotalViews,
           COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
           ARRAY_AGG(DISTINCT SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2) 
                     ORDER BY SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2)) 
                     FILTER (WHERE p.Tags IS NOT NULL) AS TopTags
    FROM Posts p
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate)
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationRank,
    ue.TotalPosts,
    ue.Questions,
    ue.Answers,
    ue.AcceptedAnswers,
    ROUND(ue.AvgPostScore, 2) AS AvgPostScore,
    ue.GoldBadges,
    COUNT(DISTINCT pe.PostId) AS HighEngagementPosts,
    AVG(pe.ViewCount) AS AvgPostViews,
    STRING_AGG(DISTINCT th.tag_path, '; ' ORDER BY th.Count DESC) AS RelatedTagPaths,
    MAX(tp.PostCount) AS PeakMonthlyActivity,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pe.Score) AS Q75PostScore,
    SUM(CASE WHEN pe.Status = 'Answered' THEN 1 ELSE 0 END)::FLOAT / 
        NULLIF(COUNT(pe.PostId), 0) AS AnswerRate,
    AVG(EXTRACT(EPOCH FROM pe.ActivePeriod) / 86400) AS AvgActiveDiscussionDays,
    ARRAY_AGG(DISTINCT pe.Title ORDER BY pe.Score DESC) 
        FILTER (WHERE pe.Score > 100)[1:5] AS TopScoringPosts,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT pl.LinkTypeId::TEXT || ':' || COUNT(*), ', ')
         FROM PostLinks pl
         JOIN Posts linked ON pl.RelatedPostId = linked.Id
         WHERE linked.OwnerUserId = ue.UserId
         GROUP BY pl.LinkTypeId), 
        'None'
    ) AS LinkStatistics,
    LAG(ue.Reputation, 1) OVER (ORDER BY ue.ReputationRank) - ue.Reputation AS ReputationGap,
    CASE 
        WHEN ue.ReputationRank <= 10 THEN 'Elite'
        WHEN ue.ReputationRank <= 100 THEN 'Expert'
        WHEN ue.ReputationRank <= 1000 THEN 'Advanced'
        ELSE 'Regular'
    END AS UserTier
FROM user_expertise ue
CROSS JOIN LATERAL (
    SELECT * FROM post_engagement pe
    WHERE pe.PostId IN (
        SELECT p.Id FROM Posts p 
        WHERE p.OwnerUserId = ue.UserId 
        ORDER BY p.Score DESC 
        LIMIT 20
    )
) pe
LEFT JOIN tag_hierarchy th ON EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = ue.UserId 
      AND p.Tags LIKE '%<' || th.TagName || '>%'
)
LEFT JOIN temporal_patterns tp ON EXISTS (
    SELECT 1 FROM Posts p
    WHERE p.OwnerUserId = ue.UserId
      AND DATE_TRUNC('month', p.CreationDate) = tp.Month
)
WHERE ue.ReputationRank <= 500
GROUP BY ue.UserId, ue.DisplayName, ue.Reputation, ue.ReputationRank, 
         ue.TotalPosts, ue.Questions, ue.Answers, ue.AcceptedAnswers, 
         ue.AvgPostScore, ue.GoldBadges, ue.ActivityRank
HAVING COUNT(DISTINCT pe.PostId) > 5
ORDER BY ue.ReputationRank, COUNT(DISTINCT pe.PostId) DESC
LIMIT 100;
