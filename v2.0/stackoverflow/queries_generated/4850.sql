-- {"query": "4850.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1316} 

WITH RankedUserEdits AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostInteractions AS (
    SELECT
        COALESCE(p.OwnerUserId, c.UserId, v.UserId) AS UserId,
        COUNT(DISTINCT p.Id) AS PostsCreatedOrEdited,
        COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) AS CommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesCast,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesCast,
        SUM(CASE WHEN p.Id IS NOT NULL THEN p.ViewCount ELSE 0 END) AS TotalPostViews
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
    GROUP BY COALESCE(p.OwnerUserId, c.UserId, v.UserId)
),
TopEditors AS (
    SELECT
        r.UserId,
        COUNT(r.PostId) AS EditsMade,
        MAX(r.EditDate) AS LastEditDate
    FROM RankedUserEdits r
    WHERE r.rn <= 5 -- Consider only top 5 edits for each user
    GROUP BY r.UserId
    HAVING COUNT(r.PostId) > 10 -- Users who made more than 10 edits in top 5
),
PostEditDetails AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.LastEditDate,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCount,
        (SELECT SUM(Score) FROM Comments WHERE PostId = p.Id) AS TotalCommentScore,
        ph.Comment AS EditComment,
        ph.Text AS EditContent,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn_edit
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
    WHERE p.CreationDate >= DATE_SUB(NOW(), INTERVAL 3 MONTH)
),
PostScores AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS NumUpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS NumDownVotes,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetScore
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY PostId
)
SELECT
    ui.UserId,
    u.DisplayName AS UserName,
    ui.PostsCreatedOrEdited,
    ui.CommentsMade,
    ui.UpVotesCast,
    ui.DownVotesCast,
    ui.TotalPostViews,
    te.EditsMade,
    te.LastEditDate,
    CASE
        WHEN u.Reputation > 100000 THEN 'Legendary'
        WHEN u.Reputation > 50000 THEN 'Expert'
        WHEN u.Reputation > 10000 THEN 'Advanced'
        WHEN u.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ReputationLevel,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 3) AS BronzeBadges,
    COALESCE(p.Title, 'N/A') AS LatestPostTitle,
    p.PostType,
    p.TotalCommentScore,
    p.EditComment,
    SUBSTRING(p.EditContent, 1, 100) AS PartialEditContent, -- Truncate for display
    ps.NetScore AS PostNetScore,
    CASE
        WHEN p.LastEditDate IS NOT NULL AND p.LastEditDate > p.CreationDate THEN TIMESTAMPDIFF(HOUR, p.CreationDate, p.LastEditDate)
        ELSE NULL
    END AS TimeToFirstEditHours,
    CASE
        WHEN u.LastAccessDate IS NULL THEN 'Never'
        ELSE DATE_FORMAT(u.LastAccessDate, '%Y-%m-%d %H:%i:%s')
    END AS FormattedLastAccessDate
FROM UserPostInteractions ui
LEFT JOIN Users u ON ui.UserId = u.Id
LEFT JOIN TopEditors te ON ui.UserId = te.UserId
LEFT JOIN PostEditDetails p ON ui.UserId = p.OwnerUserId AND p.rn_edit = 1 -- Join with the latest edit details for a user's post
LEFT JOIN PostScores ps ON p.PostId = ps.PostId
WHERE u.Views > 1000 -- Users with significant activity
ORDER BY ui.TotalPostViews DESC, ui.PostsCreatedOrEdited DESC;
