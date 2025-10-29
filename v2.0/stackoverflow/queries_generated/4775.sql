-- {"query": "4775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1117} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostCreation
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
CommentEngagement AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentRatio
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(upa.PostCount, 0) AS TotalPosts,
    COALESCE(upa.TotalScore, 0) AS TotalScoreOfPosts,
    COALESCE(upa.AvgViewCount, 0.0) AS AveragePostViews,
    COALESCE(ce.CommentCount, 0) AS TotalCommentsMade,
    COALESCE(ce.TotalCommentScore, 0) AS TotalScoreOfComments,
    CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    CASE
        WHEN u.DownVotes > u.UpVotes * 2 THEN 'High Downvote Ratio'
        WHEN u.UpVotes > u.DownVotes * 3 THEN 'High Upvote Ratio'
        ELSE 'Balanced Votes'
    END AS VoteProfile,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    CASE
        WHEN psa.LinkedPostsCount > 50 THEN 'High Linker'
        WHEN psa.DuplicateLinkCount > 10 THEN 'High Duplicate Linker'
        ELSE 'Moderate Linker'
    END AS LinkerProfile,
    COALESCE(rpe.EditType, 'No Recent Edits') AS MostRecentEditType,
    COALESCE(rpe.EditDate, u.CreationDate) AS LastEditOrCreationDate,
    CASE
        WHEN u.LastAccessDate > DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN CommentEngagement ce ON u.Id = ce.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinkAnalysis psa ON u.Id = psa.PostId
LEFT JOIN RankedPostEdits rpe ON u.Id = rpe.UserId AND rpe.rn = 1
WHERE u.Id > 1000 -- Exclude system/bot accounts
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    upa.PostCount,
    upa.TotalScore,
    upa.AvgViewCount,
    ce.CommentCount,
    ce.TotalCommentScore,
    u.WebsiteUrl,
    u.UpVotes,
    u.DownVotes,
    psa.LinkedPostsCount,
    psa.DuplicateLinkCount,
    rpe.EditType,
    rpe.EditDate,
    u.LastAccessDate
HAVING SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 5 -- Users with more than 5 gold badges
   OR COALESCE(upa.TotalScore, 0) > 100000 -- Or users with high total score on their posts
ORDER BY u.Reputation DESC
LIMIT 100;
