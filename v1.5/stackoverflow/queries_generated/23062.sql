-- {"query": "23062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 949} 

WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COALESCE(MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS HasGoldBadge
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.TagBased = TRUE
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
CorrelatedSubqueryExample AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.AvgScore,
        ups.TotalQuestionViews,
        ups.HasGoldBadge,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ups.UserId) 
         AND v.VoteTypeId = 2) AS UpvoteCount,
        COALESCE(
            (SELECT STRING_AGG(TagName, ', ') 
             FROM Tags 
             WHERE Id IN (SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))::int 
                          FROM Posts p WHERE p.OwnerUserId = ups.UserId AND p.PostTypeId = 1)),
            'No Tags'
        ) AS UserTags
    FROM UserPostStats ups
    WHERE ups.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'Closure Event'
            WHEN ph.Text IS NULL THEN 'Unknown'
            ELSE UPPER(SUBSTRING(ph.Text, 1, 10)) || '...'
        END AS EventDescription
    FROM PostHistory ph
    WHERE ph.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
)
SELECT 
    cse.UserId,
    cse.DisplayName,
    cse.Reputation,
    cse.TotalPosts,
    ROUND(cse.AvgScore, 2) AS RoundedAvgScore,
    cse.TotalQuestionViews,
    cse.HasGoldBadge,
    cse.UpvoteCount,
    cse.UserTags,
    tt.TagName AS TopTag,
    tt.TagRank,
    ra.EventDescription AS LatestEvent,
    NULLIF(pl.LinkTypeId, 3) AS NonDuplicateLinkType,  -- Example of NULL logic
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreComments
FROM CorrelatedSubqueryExample cse
INNER JOIN Posts p ON cse.UserId = p.OwnerUserId AND p.PostTypeId = 1
LEFT OUTER JOIN PostLinks pl ON p.Id = pl.PostId
FULL OUTER JOIN TopTags tt ON tt.TagId = (SELECT Id FROM Tags WHERE TagName = split_part(cse.UserTags, ', ', 1) LIMIT 1)
LEFT JOIN RecentActivity ra ON p.Id = ra.PostId AND ra.rn = 1
WHERE cse.UpvoteCount > 100 OR tt.TagRank <= 10

UNION ALL

SELECT 
    NULL AS UserId,
    'Aggregate' AS DisplayName,
    SUM(Reputation) AS Reputation,
    SUM(TotalPosts) AS TotalPosts,
    AVG(AvgScore) AS RoundedAvgScore,
    SUM(TotalQuestionViews) AS TotalQuestionViews,
    SUM(HasGoldBadge) AS HasGoldBadge,
    SUM(UpvoteCount) AS UpvoteCount,
    NULL AS UserTags,
    NULL AS TopTag,
    NULL AS TagRank,
    NULL AS LatestEvent,
    NULL AS NonDuplicateLinkType,
    NULL AS HighScoreComments
FROM CorrelatedSubqueryExample
ORDER BY Reputation DESC
LIMIT 100;
