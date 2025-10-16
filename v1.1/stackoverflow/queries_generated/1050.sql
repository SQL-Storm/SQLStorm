-- {"query": "1050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 596} 

WITH UserReputation AS (
    SELECT
        Id AS UserId,
        Reputation,
        CreationDate,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.CommentCount,
        p.AnswerCount,
        COALESCE(CAST(p.ClosedDate AS DATE), CURRENT_DATE) AS PostStatusDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
PostVoteSummary AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
),
CombinedPostData AS (
    SELECT 
        r.UserId,
        r.Reputation,
        rp.PostId,
        rp.Title,
        rp.PostStatus,
        rp.Score,
        rp.CommentCount,
        rp.AnswerCount,
        COALESCE(pvs.UpVotes, 0) AS UpVotes,
        COALESCE(pvs.DownVotes, 0) AS DownVotes
    FROM UserReputation r
    LEFT JOIN RecentPosts rp ON r.UserId = rp.OwnerUserId
    LEFT JOIN PostVoteSummary pvs ON rp.PostId = pvs.PostId
)
SELECT 
    cp.UserId,
    u.DisplayName,
    cp.Title,
    cp.PostStatus,
    cp.Reputation,
    cp.Score,
    cp.CommentCount,
    cp.AnswerCount,
    cp.UpVotes,
    cp.DownVotes,
    (cp.UpVotes - cp.DownVotes) AS VoteBalance,
    CASE
        WHEN cp.Score > 0 THEN 'Positive'
        WHEN cp.Score < 0 THEN 'Negative'
        ELSE 'Neutral'
    END AS ScoreCategory,
    STRING_AGG(CASE WHEN b.Id IS NOT NULL THEN b.Name ELSE 'No Badge' END, ', ') AS Badges
FROM CombinedPostData cp
LEFT JOIN Users u ON cp.UserId = u.Id
LEFT JOIN Badges b ON cp.UserId = b.UserId AND b.Class = 1
GROUP BY 
    cp.UserId, 
    u.DisplayName, 
    cp.Title, 
    cp.PostStatus, 
    cp.Reputation, 
    cp.Score, 
    cp.CommentCount, 
    cp.AnswerCount, 
    cp.UpVotes, 
    cp.DownVotes
ORDER BY cp.Reputation DESC, VoteBalance DESC
LIMIT 100;
