-- {"query": "4066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1252} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        p.OwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback types
),
PostEditCounts AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS PostsEditedByThisUser,
        SUM(CASE WHEN p.OwnerUserId = rpe.UserId THEN 1 ELSE 0 END) AS OwnPostsEdited,
        AVG(JULIANDAY(p.LastActivityDate) - JULIANDAY(p.CreationDate)) AS AvgPostAgeAtLastActivity
    FROM RankedPostEdits rpe
    JOIN Posts p ON rpe.PostId = p.Id
    WHERE rpe.rn = 1 -- Consider only the most recent edit/rollback for each post
    GROUP BY rpe.UserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN u.LastAccessDate > u.CreationDate THEN JULIANDAY(u.LastAccessDate) - JULIANDAY(u.CreationDate) ELSE 0 END) AS DaysSinceCreation
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.LastAccessDate, u.CreationDate
),
HighReputationUsers AS (
    SELECT Id FROM Users WHERE Reputation > 10000
),
FrequentVoters AS (
    SELECT UserId FROM Votes WHERE VoteTypeId IN (2, 3) GROUP BY UserId HAVING COUNT(*) > 500
),
RecentQuestions AS (
    SELECT Id, OwnerUserId, Title, CreationDate
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate > DATE('now', '-30 days')
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.UserViews,
    ua.CommentCount,
    ua.BadgeCount,
    pec.PostsEditedByThisUser,
    pec.OwnPostsEdited,
    pec.AvgPostAgeAtLastActivity,
    COALESCE(pec.PostsEditedByThisUser, 0) AS TotalPostsEdited,
    CASE WHEN hru.Id IS NOT NULL THEN 'HighReputation' ELSE 'StandardReputation' END AS ReputationCategory,
    CASE WHEN fv.UserId IS NOT NULL THEN 'FrequentVoter' ELSE 'OccasionalVoter' END AS VoterCategory,
    rq.Title AS RecentQuestionTitle,
    (ua.UpVoteCount - ua.DownVoteCount) AS NetVoteScore,
    IIF(ua.DaysSinceCreation > 365, 'Veteran', 'Newer') AS UserTenure,
    UPPER(SUBSTR(ua.DisplayName, 1, 3)) AS DisplayNameInitials,
    LENGTH(ua.AboutMe) AS AboutMeLength,
    (ua.CommentCount * 1.0 / NULLIF(ua.UserViews, 0)) AS CommentRatio,
    (ua.BadgeCount * 1.0 / NULLIF(ua.Reputation, 0)) AS BadgeReputationRatio,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentScoreCount,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    MAX(ph.CreationDate) AS LatestPostHistoryEntry,
    COUNT(DISTINCT pl.Id) AS PostLinkCount
FROM UserActivity ua
LEFT JOIN PostEditCounts pec ON ua.UserId = pec.UserId
LEFT JOIN RecentQuestions rq ON ua.UserId = rq.OwnerUserId
LEFT JOIN HighReputationUsers hru ON ua.UserId = hru.Id
LEFT JOIN FrequentVoters fv ON ua.UserId = fv.UserId
LEFT JOIN PostHistory ph ON ua.UserId = ph.UserId
LEFT JOIN PostLinks pl ON ua.UserId = pl.PostId OR ua.UserId = pl.RelatedPostId
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserViews,
    ua.CommentCount,
    ua.BadgeCount,
    pec.PostsEditedByThisUser,
    pec.OwnPostsEdited,
    pec.AvgPostAgeAtLastActivity,
    rq.Title,
    ua.UpVoteCount,
    ua.DownVoteCount,
    ua.DaysSinceCreation,
    ua.AboutMe
HAVING COUNT(DISTINCT ph.Id) > 10 OR COUNT(DISTINCT pl.Id) > 5
ORDER BY ua.Reputation DESC, ua.UserViews DESC
LIMIT 100;