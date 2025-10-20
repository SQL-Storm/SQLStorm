WITH RecursiveUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(COALESCE(p.Score, 0)), 0) AS TotalPostScore,
        AVG(COALESCE(vut.UpVoteCount, 0)) AS AvgUpVotesForPosts,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.CreationDate ASC) AS Rnk
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId AS OwnerUserIdWaitpostVotes,
               v.PostId,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount
        FROM Votes v
        INNER JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2, 3)
        GROUP BY p.OwnerUserId, v.PostId
    ) vut ON vut.OwnerUserIdWaitpostVotes = u.Id AND vut.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT *
FROM RecursiveUserActivity;