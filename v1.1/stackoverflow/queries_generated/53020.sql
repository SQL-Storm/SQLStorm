-- {"query": "53020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 720} 

WITH PopularTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 0
),
TopUsersPerTag AS (
    SELECT 
        pt.TagId,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS AcceptedAnswersCount,
        SUM(v.BountyAmount) AS TotalBountyEarned,
        ROW_NUMBER() OVER (PARTITION BY pt.TagId ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserRank
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id AND p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    INNER JOIN (
        SELECT 
            p2.Id AS PostId,
            unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagName
        FROM Posts p2
        WHERE p2.PostTypeId = 1
    ) AS post_tags ON post_tags.PostId = q.Id
    INNER JOIN PopularTags pt ON pt.TagName = post_tags.TagName AND pt.TagRank <= 5
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (1, 8, 9)
    WHERE p.CreationDate >= '2010-01-01' AND p.Score > 0
    GROUP BY pt.TagId, u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
UserBadgesSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserEditsSummary AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPostsCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
)
SELECT 
    pt.TagId,
    pt.TagName,
    pt.TagCount,
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.AcceptedAnswersCount,
    tu.TotalBountyEarned,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ue.EditedPostsCount,
    ue.LastEditDate,
    (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.UserId = tu.UserId) AS TotalComments
FROM TopUsersPerTag tu
INNER JOIN PopularTags pt ON pt.TagId = tu.TagId
LEFT JOIN UserBadgesSummary ub ON ub.UserId = tu.UserId
LEFT JOIN UserEditsSummary ue ON ue.UserId = tu.UserId
WHERE tu.UserRank <= 10
ORDER BY pt.TagRank ASC, tu.UserRank ASC;
