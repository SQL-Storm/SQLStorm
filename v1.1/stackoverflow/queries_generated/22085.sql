-- {"query": "22085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 735} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgePoints,
        STRING_AGG(CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END, ', ') AS TagBasedBadges
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND (u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(b.Id) > 5
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        STRING_AGG(DISTINCT SUBSTRING(p.Title, 1, 50), '; ') FILTER (WHERE p.PostTypeId = 1) AS RecentTitles,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    LEFT OUTER JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= '2020-01-01'::timestamp
      AND p.Score IS NOT NULL
    GROUP BY p.OwnerUserId, p.Id, p.Score
    HAVING SUM(p.Score) > 10
),
CommentVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS PositiveVotes
    FROM Votes v
    WHERE v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
      AND v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT 
    ub.UserId,
    ub.DisplayName,
    ub.TotalBadges,
    ub.BadgePoints,
    ps.TotalPosts,
    ps.TotalScore,
    ps.AvgScore,
    ps.TotalComments,
    cv.UpVotesGiven,
    cv.PositiveVotes,
    CASE 
        WHEN ps.TotalPosts > 0 THEN ps.TotalScore::decimal / ps.TotalPosts 
        ELSE NULL 
    END AS ScorePerPost,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = ub.UserId 
       AND p2.AcceptedAnswerId IS NOT NULL 
       AND p2.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE ParentId = p2.Id)) AS AcceptedAnswersCount,
    ub.TagBasedBadges,
    ps.RecentTitles,
    RANK() OVER (ORDER BY (ub.BadgePoints + COALESCE(ps.TotalScore, 0) + COALESCE(cv.UpVotesGiven, 0)) DESC) AS OverallRank
FROM UserBadgeStats ub
FULL OUTER JOIN PostStats ps ON ub.UserId = ps.OwnerUserId
FULL OUTER JOIN CommentVotes cv ON ub.UserId = cv.UserId
WHERE (ub.UserId IS NOT NULL OR ps.OwnerUserId IS NOT NULL OR cv.UserId IS NOT NULL)
  AND (ps.RankByScore = 1 OR ps.RankByScore IS NULL)
ORDER BY OverallRank, ub.DisplayName NULLS LAST
LIMIT 100;