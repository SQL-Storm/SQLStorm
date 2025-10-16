WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        COALESCE(u.Location, NULL) AS Location,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 0) AS QuestionsPosted,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2), 0) AS AnswersPosted,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id), 0) AS CommentsMade,
        COALESCE(u.UpVotes, 0) AS UpVotes,
        COALESCE(u.DownVotes, 0) AS DownVotes,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
        NTILE(4) OVER (ORDER BY u.Reputation) AS ReputationQuartile
    FROM Users u
), PostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedPosts,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), '; ') AS AllTags
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
    (us.UpVotes * 1.0 / NULLIF(NULLIF(us.DownVotes,0),0)) AS VoteRatio,
    COALESCE(SUM(v.BountyAmount) OVER (PARTITION BY v.UserId), 0) AS TotalBounty,
    LEAD(us.DisplayName, 1, 'None') OVER (ORDER BY us.GlobalRank) AS NextTopUser,
    CASE 
        WHEN us.ReputationQuartile = 1 THEN 'Top Quartile' 
        WHEN us.ReputationQuartile = 4 THEN 'Bottom Quartile' 
        ELSE 'Middle Quartiles' 
    END AS ReputationGroup,
    (SELECT COUNT(*) FROM PostLinks pl 
     WHERE pl.LinkTypeId = 3 AND pl.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = us.Id)
    ) AS DuplicatePostsLinked,
    us.Id,
    us.Reputation,
    us.Location,
    us.GlobalRank,
    pa.LastPostDate
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
GROUP BY
    us.DisplayName,
    us.Website,
    us.GoldBadges,
    us.QuestionsPosted,
    us.AnswersPosted,
    pa.TotalPosts,
    pa.AvgQuestionScore,
    pa.ClosedPosts,
    pa.AllTags,
    us.UpVotes,
    us.DownVotes,
    v.UserId,
    v.BountyAmount,
    us.ReputationQuartile,
    us.Id,
    us.Reputation,
    us.Location,
    us.GlobalRank,
    pa.LastPostDate
ORDER BY 
    us.GlobalRank, 
    pa.LastPostDate DESC NULLS LAST, 
    TotalBounty DESC;