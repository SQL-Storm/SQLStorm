-- {"query": "16079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 186800, "output_tokens": 173397} 
WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM AGE(u.LastAccessDate, u.CreationDate)) * 12 + 
        EXTRACT(MONTH FROM AGE(u.LastAccessDate, u.CreationDate)) AS MonthsActive,
        CASE 
            WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown'
            WHEN LENGTH(u.Location) > 50 THEN SUBSTRING(u.Location, 1, 47) || '...'
            ELSE u.Location
        END AS NormalizedLocation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) AS ReputationPercentile
    FROM Users u
    WHERE u.Reputation > 1000
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, cast('2024-10-01 12:34:56' as timestamp)) - p.CreationDate)) / 3600.0 AS HoursOpen,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId 
                           ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS AvgRecentScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserTotalPosts,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) 
                           ORDER BY p.Score DESC) AS MonthlyScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        AVG(p.Score) AS AvgPostScore,
        STDDEV(p.Score) AS StdDevScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)::FLOAT / 
            NULLIF(COUNT(*), 0) AS AcceptanceRate
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
      AND t.Count > 100
    GROUP BY t.TagName, t.Count
    HAVING COUNT(*) > 50
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyAmount,
        MIN(v.CreationDate) AS FirstVoteDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5, 8, 9)
    GROUP BY v.PostId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(*) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        MAX(c.Score) AS MaxCommentScore,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ' 
                   ORDER BY COALESCE(c.UserDisplayName, 'Anonymous')) 
            FILTER (WHERE c.Score >= 5) AS TopCommenters
    FROM Comments c
    WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    GROUP BY c.PostId
)
SELECT 
    uem.DisplayName,
    uem.NormalizedLocation,
    uem.Reputation,
    uem.ReputationRank,
    ROUND(uem.ReputationPercentile::numeric, 4) AS ReputationPercentile,
    pp.PostId,
    pt.Name AS PostType,
    pp.Score AS PostScore,
    COALESCE(pp.ViewCount, 0) AS Views,
    pp.HoursOpen,
    CASE 
        WHEN pp.PrevPostScore IS NULL THEN NULL
        WHEN pp.PrevPostScore = 0 THEN NULL
        ELSE ROUND(((pp.Score - pp.PrevPostScore)::FLOAT / NULLIF(ABS(pp.PrevPostScore), 0) * 100)::numeric, 2)
    END AS ScoreChangePercent,
    ROUND(COALESCE(pp.AvgRecentScore, 0)::numeric, 2) AS AvgRecentScore,
    pp.UserTotalPosts,
    COALESCE(vp.UpvoteCount, 0) - COALESCE(vp.DownvoteCount, 0) AS NetVotes,
    COALESCE(vp.TotalBountyAmount, 0) AS BountyEarned,
    COALESCE(ca.TotalComments, 0) AS CommentCount,
    ROUND(COALESCE(ca.AvgCommentLength, 0)::numeric, 2) AS AvgCommentLength,
    ca.TopCommenters,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = uem.Id 
       AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = uem.Id 
       AND b.Class = 2) AS SilverBadges,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(Tags, 2, LENGTH(Tags)-2), ', ')
     FROM Posts p2
     WHERE p2.OwnerUserId = uem.Id
       AND p2.PostTypeId = 1
       AND p2.Tags IS NOT NULL
       AND p2.Score > 10
     LIMIT 1) AS TopTags,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Posts p3 
                    WHERE p3.OwnerUserId = uem.Id 
                      AND p3.AcceptedAnswerId IS NOT NULL) 
        THEN 'Yes' 
        ELSE 'No' 
    END AS HasAcceptedAnswers
FROM UserEngagementMetrics uem
INNER JOIN PostPerformance pp ON uem.Id = pp.OwnerUserId
INNER JOIN PostTypes pt ON pp.PostTypeId = pt.Id
LEFT OUTER JOIN VotePatterns vp ON pp.PostId = vp.PostId
LEFT OUTER JOIN CommentActivity ca ON pp.PostId = ca.PostId
WHERE pp.Score > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) 
                  FROM Posts 
                  WHERE PostTypeId IN (1, 2))
  AND (pp.MonthlyScoreRank <= 10 OR pp.HasAcceptedAnswer = 1)
  AND uem.MonthsActive > 6
  AND NOT EXISTS (
      SELECT 1 
      FROM Votes v2 
      WHERE v2.PostId = pp.PostId 
        AND v2.VoteTypeId IN (4, 12)
  )
ORDER BY 
    uem.ReputationPercentile DESC,
    pp.Score DESC,
    COALESCE(vp.UpvoteCount, 0) DESC
LIMIT 1000;