-- {"query": "42045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 969} 

WITH RECURSIVE PostHierarchy AS (
    SELECT Id, PostTypeId, ParentId, CreationDate, Score, ViewCount, Body, OwnerUserId, Title, Tags, AnswerCount, CommentCount, FavoriteCount, 1 AS Depth
    FROM Posts
    WHERE ParentId IS NULL
    UNION ALL
    SELECT p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Body, p.OwnerUserId, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, ph.Depth + 1
    FROM Posts p
    JOIN PostHierarchy ph ON p.ParentId = ph.Id
),
UserActivity AS (
    SELECT u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.WebsiteUrl, u.Location, u.AboutMe, u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.EmailHash, u.AccountId,
           COUNT(DISTINCT ph.PostId) AS PostEdits,
           COUNT(DISTINCT v.PostId) AS VotesCast,
           COUNT(DISTINCT c.PostId) AS CommentsPosted,
           COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
TagStats AS (
    SELECT t.TagName, COUNT(DISTINCT p.Id) AS PostCount, SUM(p.ViewCount) AS TotalViews, SUM(p.Score) AS TotalScore
    FROM Tags t
    JOIN Posts p ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '"><'))
    GROUP BY t.TagName
),
PostHistorySummary AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.UserDisplayName, ph.Comment, ph.Text,
           COUNT(*) OVER (PARTITION BY ph.PostId) AS TotalRevisions,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RevisionRank
    FROM PostHistory ph
),
PostMetrics AS (
    SELECT p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Body, p.OwnerUserId, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount,
           COUNT(DISTINCT v.Id) AS TotalVotes,
           COUNT(DISTINCT c.Id) AS TotalComments,
           MAX(phs.TotalRevisions) AS MaxRevisions
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistorySummary phs ON p.Id = phs.PostId
    GROUP BY p.Id
)
SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.UserDisplayName, ph.Comment, ph.Text,
       ua.DisplayName AS UserDisplayName, ua.Reputation, ua.UpVotes, ua.DownVotes,
       pm.Score, pm.ViewCount, pm.TotalVotes, pm.TotalComments, pm.MaxRevisions,
       ts.TagName, ts.PostCount, ts.TotalViews, ts.TotalScore
FROM PostHistorySummary ph
JOIN Users ua ON ph.UserId = ua.Id
JOIN PostMetrics pm ON ph.PostId = pm.Id
LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(pm.Tags, 2, length(pm.Tags)-2), '"><')) AS TagName
) t(TagName) ON true
LEFT JOIN TagStats ts ON t.TagName = ts.TagName
WHERE ph.RevisionRank = 1
ORDER BY ph.CreationDate DESC
LIMIT 1000;
