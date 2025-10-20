WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        u.Reputation > 1000 AND p.CommunityOwnedDate IS NULL AND p.PostTypeId IN (1, 2)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    ORDER BY
        TotalScore DESC
    LIMIT 10
),
ActivitySummary AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.LastActivityDate,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.OwnerUserId IN (SELECT UserId FROM TopUsers)
    GROUP BY
        p.OwnerUserId, p.Id, p.PostTypeId, p.CreationDate, p.LastActivityDate
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalScore,
    (tu.TotalPosts * 1.0 / (SELECT COUNT(p.Id) FROM Posts p)) * 100 AS PercentActiveQuestionsRequested,
    tu.TotalQuestionViews,
    tu.TotalComments,
    tu.TotalVotes,
    COUNT(DISTINCT a.PostId) AS ActivePosts,
    AVG(a.TotalEdits) AS AvgEditsPerPost,
    AVG(a.TotalVotes) AS AvgVotesPerPost,
    AVG(a.TotalComments) AS AvgCommentsPerPost,
    AVG(EXTRACT(EPOCH FROM (a.LastActivityDate - a.CreationDate)) / 3600.0) AS AvgActivityHoursPerPost
FROM
    TopUsers tu
JOIN
    ActivitySummary a ON tu.UserId = a.OwnerUserId
GROUP BY
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalScore,
    tu.TotalQuestionViews,
    tu.TotalComments,
    tu.TotalVotes
ORDER BY
    ActivePosts DESC;