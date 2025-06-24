
WITH VoteCounts AS (
    SELECT 
        Posts.Id AS PostId,
        COUNT(Votes.Id) AS TotalVotes,
        DATE_FORMAT(Votes.CreationDate, '%Y-%m-01') AS VoteMonth
    FROM 
        Posts
    LEFT JOIN 
        Votes ON Posts.Id = Votes.PostId
    GROUP BY 
        Posts.Id, VoteMonth
),
AvgVotePerPost AS (
    SELECT 
        VoteMonth,
        AVG(TotalVotes) AS AvgVotes
    FROM 
        VoteCounts
    GROUP BY 
        VoteMonth
)
SELECT 
    VoteMonth,
    AvgVotes
FROM 
    AvgVotePerPost
ORDER BY 
    VoteMonth DESC;
