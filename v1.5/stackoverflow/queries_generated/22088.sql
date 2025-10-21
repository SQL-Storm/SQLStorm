-- {"query": "22088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 784} 
WITH UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(LENGTH(p.Body)) AS AvgBodyLength,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.Score IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 100 WHEN b.Class = 2 THEN 10 ELSE 1 END) AS BadgePoints,
        STRING_AGG(DISTINCT b.Name, '; ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.TotalScore, 0) AS TotalScore,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.BadgePoints, 0) AS BadgePoints,
        ups.AvgBodyLength,
        ROW_NUMBER() OVER (ORDER BY COALESCE(ups.TotalScore, 0) + COALESCE(ubs.BadgePoints, 0) DESC) AS Rank
    FROM Users u
    LEFT OUTER JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT OUTER JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 100 AND (ups.TotalPosts IS NOT NULL OR ubs.TotalBadges IS NOT NULL)
),
EditedPosts AS (
    SELECT DISTINCT ph.PostId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
      AND ph.CreationDate > '2008-01-01 00:00:00'
),
UserComments AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    GROUP BY c.UserId
)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.TotalPosts,
    tu.TotalScore,
    tu.TotalBadges,
    tu.BadgePoints,
    tu.AvgBodyLength,
    tu.Rank,
    COALESCE(uc.CommentCount, 0) AS CommentCount,
    COALESCE(uc.AvgCommentLength, 0) AS AvgCommentLength,
    CASE 
        WHEN tu.TotalScore > 1000 THEN 'Expert'
        WHEN tu.TotalScore > 100 THEN 'Contributor'
        ELSE 'Beginner'
    END AS UserLevel,
    (SELECT COUNT(*) FROM EditedPosts ep WHERE ep.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = tu.Id AND p.PostTypeId = 1
    )) AS EditedQuestions,
    tu.TotalScore + tu.BadgePoints AS CompositeScore
FROM TopUsers tu
LEFT OUTER JOIN UserComments uc ON tu.Id = uc.UserId
WHERE tu.Rank <= 100
  AND EXISTS (
      SELECT 1 FROM Votes v WHERE v.UserId = tu.Id AND v.VoteTypeId IN (2, 3) AND v.PostId IS NOT NULL
  )
  AND tu.Id IN (
      SELECT DISTINCT p.OwnerUserId FROM Posts p WHERE p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%'
  )
ORDER BY tu.Rank, tu.Id;