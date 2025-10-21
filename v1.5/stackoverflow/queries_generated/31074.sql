-- {"query": "31074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 318} 

WITH RecentActivePosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.AnswerCount, p.TagCount,
           ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '6 months'
), 
TopUsers AS (
    SELECT u.Id, u.DisplayName, SUM(v.VoteTypeId = 2) AS UpVotes, SUM(v.VoteTypeId = 3) AS DownVotes
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id
), 
PostDetails AS (
    SELECT rp.Id AS PostId, 
           rp.Title, 
           rp.ViewCount, 
           rp.Score, 
           ra.UserId AS AuthorId, 
           tu.DisplayName AS AuthorDisplayName, 
           tu.UpVotes AS AuthorUpVotes, 
           tu.DownVotes AS AuthorDownVotes
    FROM RecentActivePosts rp
    JOIN Posts ra ON rp.Id = ra.Id
    JOIN TopUsers tu ON ra.OwnerUserId = tu.Id
)
SELECT pd.Title, 
       pd.ViewCount, 
       pd.Score, 
       pd.AuthorDisplayName, 
       pd.AuthorUpVotes, 
       pd.AuthorDownVotes
FROM PostDetails pd
ORDER BY pd.Score DESC, pd.ViewCount DESC
LIMIT 10;
