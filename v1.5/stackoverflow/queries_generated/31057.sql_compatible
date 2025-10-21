WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(pc.CommentCount) AS TotalComments,
        AVG(u.Reputation) AS AvgReputation
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) pc ON pc.PostId = p.Id
    WHERE 
        u.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY 
        u.Id,
        u.DisplayName
),
TopUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.UpVotes,
        ua.DownVotes,
        ua.TotalComments,
        ua.AvgReputation,
        RANK() OVER (ORDER BY ua.PostCount DESC, ua.UpVotes DESC) AS Rank
    FROM 
        UserActivity ua
)
SELECT 
    UserId,
    DisplayName,
    PostCount,
    QuestionCount,
    AnswerCount,
    UpVotes,
    DownVotes,
    TotalComments,
    AvgReputation,
    Rank
FROM 
    TopUsers
WHERE 
    Rank <= 10
ORDER BY 
    Rank;