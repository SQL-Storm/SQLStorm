
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(IFNULL(p.Score, 0)) AS AvgScore,
        SUM(IFNULL(p.ViewCount, 0)) AS TotalViews,
        SUM(IFNULL(b.Class, 0)) AS TotalBadges,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        pt.Name AS PostType,
        IFNULL(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes, 
        IFNULL(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        IFNULL(SUM(CASE WHEN v.VoteTypeId = 4 THEN 1 ELSE 0 END), 0) AS OffensiveVotes
    FROM 
        Posts p
    LEFT JOIN 
        VoteTypes vt ON p.Id = vt.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY 
        p.Id, p.Title, p.CreationDate, pt.Name
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        AvgScore,
        TotalViews,
        TotalBadges,
        TotalComments,
        @rownum := @rownum + 1 AS PostRank
    FROM 
        UserStats, (SELECT @rownum := 0) r
    ORDER BY 
        TotalPosts DESC
)
SELECT 
    tu.DisplayName,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AvgScore,
    tu.TotalViews,
    tu.TotalBadges,
    tu.TotalComments,
    pp.Title,
    pp.UpVotes,
    pp.DownVotes,
    pp.OffensiveVotes
FROM 
    TopUsers tu
JOIN 
    PostPerformance pp ON tu.UserId = pp.PostId
WHERE 
    tu.PostRank <= 10
ORDER BY 
    tu.TotalPosts DESC, pp.UpVotes DESC;
