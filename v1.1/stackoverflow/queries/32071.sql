-- {"query": "32071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 462} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS TotalPosts, 
        COUNT(DISTINCT c.Id) AS TotalComments, 
        COUNT(DISTINCT v.Id) AS TotalVotes, 
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2022-01-01'
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName,
        (TotalPosts + TotalComments + TotalVotes + TotalBadges) AS TotalActions
    FROM UserActivity
    ORDER BY TotalActions DESC
    LIMIT 10
),
TopQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.CreationDate, 
        (
            SELECT COUNT(DISTINCT v.Id)
            FROM Votes v
            WHERE v.PostId = p.Id AND v.VoteTypeId = 2
        ) AS UpVotes,
        (
            SELECT COUNT(DISTINCT v.Id)
            FROM Votes v
            WHERE v.PostId = p.Id AND v.VoteTypeId = 3
        ) AS DownVotes
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2022-01-01'
    ORDER BY UpVotes DESC, DownVotes ASC, p.ViewCount DESC
    LIMIT 10
)
SELECT 
    tu.DisplayName AS UserDisplayName, 
    tq.Title AS QuestionTitle, 
    tq.Score AS QuestionScore, 
    tq.ViewCount AS QuestionViews,
    tq.UpVotes AS QuestionUpVotes,
    tq.DownVotes AS QuestionDownVotes
FROM TopUsers tu
CROSS JOIN TopQuestions tq
ORDER BY tq.UpVotes DESC, tq.DownVotes ASC;