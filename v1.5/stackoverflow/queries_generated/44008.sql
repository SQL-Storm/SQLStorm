-- {"query": "44008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 18352, "output_tokens": 7406} 
Here is an elaborate and interesting SQL query for performance benchmarking:

WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, 
           u.Reputation, u.CreationDate AS UserCreationDate, u.Views, u.UpVotes, u.DownVotes,
           b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased,
           l.Id AS LinkId, l.LinkTypeId, l.RelatedPostId,
           v.Id AS VoteId, v.VoteTypeId, v.CreationDate AS VoteCreationDate, v.BountyAmount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostLinks l ON p.Id = l.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate BETWEEN '2021-01-01' AND '2021-12-31'
),
aggregated AS (
    SELECT Id, PostTypeId, OwnerUserId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount,
           Reputation, UserCreationDate, Views, UpVotes, DownVotes,
           COUNT(DISTINCT BadgeId) AS NumBadges,
           COUNT(DISTINCT CASE WHEN BadgeTagBased = 1 THEN BadgeId END) AS NumTagBadges,
           COUNT(DISTINCT CASE WHEN BadgeClass = 1 THEN BadgeId END) AS NumGoldBadges,
           COUNT(DISTINCT CASE WHEN BadgeClass = 2 THEN BadgeId END) AS NumSilverBadges,
           COUNT(DISTINCT CASE WHEN BadgeClass = 3 THEN BadgeId END) AS NumBronzeBadges,
           COUNT(DISTINCT LinkId) AS NumLinks,
           COUNT(DISTINCT CASE WHEN LinkTypeId = 1 THEN LinkId END) AS NumLinkedPosts,
           COUNT(DISTINCT CASE WHEN LinkTypeId = 3 THEN LinkId END) AS NumDuplicatePosts,
           COUNT(DISTINCT VoteId) AS NumVotes,
           COUNT(DISTINCT CASE WHEN VoteTypeId = 2 THEN VoteId END) AS NumUpVotes,
           COUNT(DISTINCT CASE WHEN VoteTypeId = 3 THEN VoteId END) AS NumDownVotes,
           COUNT(DISTINCT CASE WHEN VoteTypeId = 8 THEN VoteId END) AS NumBountyStarts,
           COUNT(DISTINCT CASE WHEN VoteTypeId = 9 THEN VoteId END) AS NumBountyClosed,
           SUM(BountyAmount) AS TotalBounty
    FROM cte
    GROUP BY Id, PostTypeId, OwnerUserId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount,
             Reputation, UserCreationDate, Views, UpVotes, DownVotes
)
SELECT *
FROM aggregated
ORDER BY NumVotes DESC
LIMIT 100;