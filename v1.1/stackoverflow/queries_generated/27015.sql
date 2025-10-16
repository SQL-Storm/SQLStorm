-- {"query": "27015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 796} 

WITH ActiveUsers AS (
    SELECT
        Id,
        Reputation,
        CreationDate,
        LastAccessDate,
        Views,
        UpVotes,
        DownVotes,
        COALESCE(EmailHash, 'No email') AS EmailHash,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        Users
    WHERE
        LastAccessDate > NOW() - INTERVAL '30 days'
    ),
    HighScorePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COUNT(c.Id) AS CommentCount,
        p.ParentId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate  AS EditorDate,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.AcceptedAnswerId, p.ParentId, ph.PostHistorTypeId, ph.UserId, ph.CreationDate
    HAVING
        COUNT(c.Id) > 0
)
SELECT
    au.Id AS UserId,
    au.Reputation,
    au.CreationDate AS UserCreationDate,
    au.LastAccessDate,
    au.Views AS UserViews,
    au.UpVotes AS UserUpVotes,
    au.DownVotes AS UserDownVotes,
    au.EmailHash,
    au.ReputationRank,
    hsp.PostId,
    hsp.PostTypeId,
    hsp.OwnerUserId,
    hsp.CreationDate AS PostCreationDate,
    hsp.Score AS PostScore,
    hsp.ViewCount,
    hsp.Title,
    hsp.Tags,
    hsp.CommentCount,
    hsp. AcceptedAnswerId AS PostAcceptedAnswerId,
    hsp.ParentId,
    hsp.PostHistoryTypeId,
    hsp.EditorDate,
    hsp.UpVoteCount AS PostUpVoteCount,
    hsp.DownVotesCount

FROM
    ActiveUsers au
LEFT JOIN
    HighScorePosts hsp ON au.Id = hsp.OwnerUserId
    order by au.Views DESC
LIMIT 100;
