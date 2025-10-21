WITH PostStats AS (
    SELECT 
        OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided
    FROM Posts p
    WHERE p.CreationDate >= DATE '2020-01-01' AND p.PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
    HAVING COUNT(p.Id) > 50
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(CARDINALITY(REGEXP_SPLIT_TO_ARRAY(c.Text, E'\\\\s+'))) AS AvgCommentLength,
        MAX(c.Score) AS TopCommentScore
    FROM Comments c
    WHERE c.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    GROUP BY c.UserId
),
VoteStats AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        SUM(v.BountyAmount) AS TotalBountySpent
    FROM Votes v
    WHERE v.CreationDate >= DATE '2019-01-01'
    GROUP BY v.UserId
),
BadgeAchievers AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Name) AS UniqueBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.Class IN (1, 2)
    GROUP BY b.UserId
    HAVING COUNT(b.Id) >= 10
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    ps.TotalPosts,
    vs.UpvotesGiven,
    vs.DownvotesReceived,
    ba.UniqueBadges,
    ROW_NUMBER() OVER (PARTITION BY ba.UniqueBadges ORDER BY u.Reputation DESC) AS ReputationRankInBadgeGroup,
    (
     SELECT STRING_AGG(DISTINCT t.TagName, '; ')
     FROM Posts p
     JOIN UNNEST(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS t(TagName)
     ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    ) AS FrequentTags
FROM Users AS u
JOIN PostStats ps ON u.Id = ps.UserId
LEFT JOIN CommentStats cs ON u.Id = cs.UserId
JOIN VoteStats vs ON u.Id = vs.UserId
JOIN BadgeAchievers ba ON u.Id = ba.UserId
WHERE u.Reputation > 10000
    AND u.CreationDate < DATE '2022-01-01'
    AND EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = u.Id AND AnswerCount > 5)
ORDER BY ReputationRankInBadgeGroup, u.Reputation DESC
LIMIT 100;