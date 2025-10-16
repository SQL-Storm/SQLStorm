-- {"query": "14050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 119085, "output_tokens": 50923} 
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         u.Id AS UserId, u.Reputation, u.CreationDate AS UserCreationDate, u.DownVotes, u.UpVotes, u.Views,
         COALESCE(DATEDIFF(p.CreationDate, u.CreationDate), 0) AS UserPostAgeInDays,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
         CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'Not Community Owned' END AS PostOwnership,
         CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS PostType,
         STRING_AGG(DISTINCT t.TagName, '><') AS Tags,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
         SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
         SUM(CASE WHEN v.VoteTypeId = 11 THEN 1 ELSE 0 END) AS Undeletes,
         SUM(CASE WHEN v.VoteTypeId = 12 THEN 1 ELSE 0 END) AS Spam,
         SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END) AS ModeratorNominations,
         SUM(CASE WHEN v.VoteTypeId = 15 THEN 1 ELSE 0 END) AS ModeratorReviews,
         SUM(CASE WHEN v.VoteTypeId = 16 THEN 1 ELSE 0 END) AS EditSuggestionApprovals
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Tags t ON CHARINDEX('><' + t.TagName + '><', '><' + p.Tags + '><') > 0
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
           u.Id, u.Reputation, u.CreationDate, u.DownVotes, u.UpVotes, u.Views
)
SELECT *,
       CASE WHEN PostStatus = 'Closed' THEN 'Closed' ELSE 'Open' END AS FinalPostStatus,
       CASE WHEN PostOwnership = 'Community Owned' THEN 'Community Owned' ELSE 'Not Community Owned' END AS FinalPostOwnership,
       CASE WHEN PostType = 'Question' THEN 'Question' WHEN PostType = 'Answer' THEN 'Answer' ELSE 'Other' END AS FinalPostType,
       CASE WHEN Tags LIKE '%><google%' OR Tags LIKE '%><java%' THEN 'Technical' WHEN Tags LIKE '%><discussion%' OR Tags LIKE '%><subjective%' THEN 'Discussion' ELSE 'Other' END AS PostCategory,
       ROUND(POWER(2, LOG(10, COALESCE(UpVotes - DownVotes, 0) + 1)), 2) AS PostScore,
       ROUND(COALESCE(FavoriteCount * 1.0 / POWER(DATEDIFF(CURRENT_TIMESTAMP, CreationDate), 1.5), 0), 2) AS PostPopularity,
       ROUND(COALESCE(UpVotes * 1.0 / GREATEST(1, UserUpVotes), 0), 2) AS UserUpVoteRate,
       ROUND(COALESCE(DownVotes * 1.0 / GREATEST(1, UserDownVotes), 0), 2) AS UserDownVoteRate,
       CASE WHEN PostType = 'Question' AND DATEDIFF(CURRENT_TIMESTAMP, CreationDate) <= 30 AND AnswerCount = 0 AND UpVotes >= 5 THEN 'Unanswered' ELSE 'Answered' END AS AnswerStatus
FROM cte;