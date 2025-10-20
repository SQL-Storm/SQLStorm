WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalAnswers,
        TotalComments,
        TotalUpvotes,
        TotalDownvotes
    FROM
        ActiveUsers
    WHERE
        Reputation > 1000
),
PopularPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        COUNT(v.Id) AS TotalVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT l.RelatedPostId) AS TotalLinks,
        p.OwnerUserId
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostLinks l ON p.Id = l.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.AnswerCount, u.DisplayName, p.OwnerUserId
    HAVING
        COUNT(v.Id) > 10
),
EngagedUsers AS (
    SELECT
        hr.UserId,
        hr.Reputation,
        hr.UserCreationDate,
        hr.TotalPosts,
        hr.TotalAnswers,
        hr.TotalComments,
        hr.TotalUpvotes,
        hr.TotalDownvotes,
        COUNT(DISTINCT pp.PostId) AS InteractedPosts
    FROM
        HighReputationUsers hr
    LEFT JOIN
        PopularPosts pp ON hr.UserId = pp.OwnerUserId
    GROUP BY
        hr.UserId, hr.Reputation, hr.UserCreationDate, hr.TotalPosts, hr.TotalAnswers, hr.TotalComments, hr.TotalUpvotes, hr.TotalDownvotes
    HAVING
        COUNT(DISTINCT pp.PostId) > 5
)
SELECT
    eu.UserId,
    eu.Reputation,
    eu.UserCreationDate,
    eu.TotalPosts,
    eu.TotalAnswers,
    eu.TotalComments,
    eu.TotalUpvotes,
    eu.TotalDownvotes,
    eu.InteractedPosts,
    AVG(pp.Score) AS AvgPostScore,
    AVG(pp.ViewCount) AS AvgPostViewCount,
    MAX(pp.AnswerCount) AS MaxAnswerCount,
    MAX(pp.TotalVotes) AS MaxVotes,
    MAX(pp.TotalComments) AS MaxComments,
    MAX(pp.TotalLinks) AS MaxLinks
FROM
    EngagedUsers eu
JOIN
    PopularPosts pp ON eu.UserId = pp.OwnerUserId
GROUP BY
    eu.UserId, eu.Reputation, eu.UserCreationDate, eu.TotalPosts, eu.TotalAnswers, eu.TotalComments, eu.TotalUpvotes, eu.TotalDownvotes, eu.InteractedPosts
ORDER BY
    eu.Reputation DESC, eu.InteractedPosts DESC
LIMIT 100;