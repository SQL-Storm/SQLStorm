WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsPosted,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswersPosted,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsMade,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
        NTILE(4) OVER (ORDER BY u.Reputation) AS ReputationQuartile,
        u.UpVotes,
        u.DownVotes,
        u.Location
    FROM Users u
), PostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedPosts,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '; ') AS AllTags
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY p.OwnerUserId
)
SELECT 
    us.DisplayName,
    us.Website,
    us.GoldBadges,
    us.QuestionsPosted,
    us.AnswersPosted,
    pa.TotalPosts,
    pa.AvgQuestionScore,
    pa.ClosedPosts,
    pa.AllTags,
    (CASE
        WHEN us.DownVotes IS NULL OR us.DownVotes = 0 THEN NULL
        ELSE (CAST(us.UpVotes AS DOUBLE PRECISION) / NULLIF(CAST(us.DownVotes AS DOUBLE PRECISION), 0))
     END) AS VoteRatio,
    COALESCE(SUM(v.BountyAmount) OVER (PARTITION BY v.UserId), 0) AS TotalBounty,
    LEAD(us.DisplayName, 1, 'None') OVER (ORDER BY us.GlobalRank) AS NextTopUser,
    CASE 
        WHEN us.ReputationQuartile = 1 THEN 'Top Quartile' 
        WHEN us.ReputationQuartile = 4 THEN 'Bottom Quartile' 
        ELSE 'Middle Quartiles' 
    END AS ReputationGroup,
    (SELECT COUNT(*) FROM PostLinks pl 
     WHERE pl.LinkTypeId = 3 AND pl.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = us.Id)) AS DuplicatePostsLinked
FROM UserStats us
LEFT JOIN PostActivity pa ON us.Id = pa.OwnerUserId
LEFT JOIN Votes v ON v.UserId = us.Id AND v.VoteTypeId = 8
WHERE us.Reputation > 1000
    AND (us.Location LIKE '%USA%' OR us.Location IS NULL)
    AND EXISTS (
        SELECT 1 FROM Badges b 
        WHERE b.UserId = us.Id AND b.Name = 'Legendary' 
        INTERSECT 
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = us.Id AND p.AcceptedAnswerId IS NOT NULL
    )
ORDER BY 
    us.GlobalRank, 
    pa.LastPostDate DESC NULLS LAST, 
    TotalBounty DESC;