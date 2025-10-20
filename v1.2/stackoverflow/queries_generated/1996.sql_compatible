WITH RecursiveLateIamges AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           COALESCE(u.Reputation, 0) AS Reputation,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= u.CreationDate AND p.CreationDate <= u.CreationDate + INTERVAL '30 day') AS RecentQuestions,
           RANK() OVER (PARTITION BY LENGTH(u.DisplayName) % 5 ORDER BY u.Reputation DESC, u.CreationDate DESC) AS FamousRankGrouping
    FROM Users u
    LEFT JOIN Posts p 
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
CmpAnsVotesWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ParentId,
        VOTEUP.TotalUp,
        VOTEDN.TotalDown,
        VO.TypeName,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(p.Tags, '') ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS TotalUp
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) VOTEUP ON VOTEUP.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS TotalDown
        FROM Votes
        WHERE VoteTypeId = 3
        GROUP BY PostId
    ) VOTEDN ON VOTEDN.PostId = p.Id
    LEFT JOIN (
        SELECT Id, Name AS TypeName
        FROM PostTypes
    ) VO ON VO.Id = p.PostTypeId
    WHERE p.PostTypeId IN (1, 2)
)
SELECT rli.UserId,
       rli.DisplayName,
       rli.Reputation,
       rli.RecentQuestions,
       rli.FamousRankGrouping,
       cavw.Id AS PostId,
       cavw.PostTypeId,
       cavw.OwnerUserId,
       cavw.CreationDate AS PostCreationDate,
       cavw.Score,
       cavw.ParentId,
       cavw.TotalUp,
       cavw.TotalDown,
       cavw.TypeName,
       cavw.rn
FROM RecursiveLateIamges rli
JOIN CmpAnsVotesWindow cavw
    ON cavw.OwnerUserId = rli.UserId
ORDER BY rli.Reputation DESC, cavw.Score DESC;