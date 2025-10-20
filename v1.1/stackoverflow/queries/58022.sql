WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(b.Id) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersGenerated,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 YEAR'
    GROUP BY p.OwnerUserId, p.PostTypeId
),
VoteAggregates AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
TaggedPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        TRIM(tag) AS Tag
    FROM Posts p,
    LATERAL (
      SELECT UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.GoldBadges,
    ps.PostTypeId,
    pt.Name AS PostType,
    ps.TotalPosts,
    ps.TotalAnswersGenerated,
    ps.AvgAnswerScore,
    ps.TotalViews,
    COALESCE(SUM(va.UpVotes), 0) AS TotalUpVotes,
    COALESCE(SUM(va.DownVotes), 0) AS TotalDownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COALESCE(ed.EditsMade, 0) AS EditsMade,
    COALESCE(rt.RelevantTagsUsed, 0) AS RelevantTagsUsed,
    RANK() OVER (ORDER BY au.Reputation DESC) AS ReputationRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
JOIN PostTypes pt ON ps.PostTypeId = pt.Id
LEFT JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN VoteAggregates va ON p.Id = va.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN (
    SELECT ph.UserId, COUNT(*) AS EditsMade
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
    GROUP BY ph.UserId
) ed ON ed.UserId = au.Id
LEFT JOIN (
    SELECT tp.OwnerUserId, COUNT(DISTINCT tp.Tag) AS RelevantTagsUsed
    FROM TaggedPosts tp
    WHERE LOWER(tp.Tag) IN ('sql','performance','optimization')
    GROUP BY tp.OwnerUserId
) rt ON rt.OwnerUserId = au.Id
GROUP BY 
    au.Id,
    au.DisplayName, 
    au.Reputation, 
    au.GoldBadges, 
    ps.PostTypeId, 
    pt.Name, 
    ps.TotalPosts, 
    ps.TotalAnswersGenerated, 
    ps.AvgAnswerScore, 
    ps.TotalViews,
    ed.EditsMade,
    rt.RelevantTagsUsed
HAVING COUNT(DISTINCT p.Id) > 50 AND COALESCE(SUM(va.UpVotes), 0) > 100
ORDER BY 
    au.Reputation DESC, 
    TotalUpVotes DESC, 
    TotalViews DESC
LIMIT 100;