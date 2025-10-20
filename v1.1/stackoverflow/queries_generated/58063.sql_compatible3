WITH UserContributions AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10) AS ClosedPosts,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND pl.LinkTypeId = 3) AS DuplicateLinks
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE (p.CreationDate >= DATE '2015-01-01' OR p.CreationDate IS NULL)
    GROUP BY u.Id, u.Reputation, u.CreationDate
)
SELECT 
    uc.UserId,
    uc.Reputation,
    uc.TotalPosts,
    uc.TotalComments,
    uc.TotalVotes,
    uc.GoldBadges,
    uc.AvgPostScore,
    uc.ReputationRank,
    uc.AcceptedAnswers,
    uc.ClosedPosts,
    uc.DuplicateLinks,
    (
      SELECT STRING_AGG(t.TagName, ', ')
      FROM Tags t
      WHERE t.Id IN (
        SELECT DISTINCT tag_id
        FROM (
          SELECT
            tag_name,
            (SELECT Id FROM Tags tt WHERE tt.TagName = tag_name LIMIT 1) AS tag_id
          FROM (
            SELECT
              regexp_split_to_table(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><') AS tag_name
            FROM Posts p
            WHERE p.OwnerUserId = uc.UserId AND p.PostTypeId = 1
          ) p_tags
        ) sub
        WHERE tag_id IS NOT NULL
      )
    ) AS TopTags,
    DENSE_RANK() OVER (ORDER BY uc.TotalPosts + uc.TotalComments + uc.TotalVotes DESC) AS ActivityRank,
    CASE 
        WHEN uc.Reputation > 100000 THEN 'Legendary'
        WHEN uc.Reputation > 50000 THEN 'Epic'
        WHEN uc.Reputation > 10000 THEN 'Advanced'
        ELSE 'Standard'
    END AS ReputationTier
FROM UserContributions uc
ORDER BY 
    uc.Reputation DESC, 
    ActivityRank, 
    uc.AvgPostScore DESC 
LIMIT 100;