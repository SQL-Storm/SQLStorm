-- {"query": "4749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1166} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditFrequency AS (
    SELECT
        pe.UserId,
        COUNT(DISTINCT pe.PostId) AS DistinctPostsEdited,
        AVG(julianday('now') - julianday(u.CreationDate)) AS AvgUserAgeAtEdit
    FROM RankedPostEdits pe
    JOIN Users u ON pe.UserId = u.Id
    WHERE pe.rn = 1
    GROUP BY pe.UserId
),
TopEditors AS (
    SELECT
        UserId
    FROM PostEditFrequency
    ORDER BY DistinctPostsEdited DESC
    LIMIT 10
),
UserPostContributions AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(upc.PostCount, 0) AS TotalPosts,
        COALESCE(upc.QuestionCount, 0) AS Questions,
        COALESCE(upc.AnswerCount, 0) AS Answers,
        COALESCE(uvs.UpVoteCount, 0) AS TotalUpvotesGiven,
        COALESCE(uvs.DownVoteCount, 0) AS TotalDownvotesGiven,
        COALESCE(uvs.TotalBountyGiven, 0) AS TotalBounty,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        CASE WHEN EXISTS (SELECT 1 FROM TopEditors te WHERE te.UserId = u.Id) THEN 'TopEditor' ELSE 'Regular' END AS EditorStatus
    FROM Users u
    LEFT JOIN UserPostContributions upc ON u.Id = upc.OwnerUserId
    LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.TotalUpvotesGiven,
    upa.TotalDownvotesGiven,
    upa.TotalBounty,
    upa.GoldBadges,
    upa.SilverBadges,
    upa.BronzeBadges,
    upa.EditorStatus,
    CASE
        WHEN upa.TotalPosts > 1000 AND upa.TotalUpvotesGiven > 5000 THEN 'High Engagement'
        WHEN upa.Questions > 100 AND upa.Answers > 500 THEN 'Content Producer'
        WHEN upa.GoldBadges > 5 THEN 'Community Leader'
        WHEN upa.EditorStatus = 'TopEditor' AND upa.TotalPosts > 50 THEN 'Proactive Editor'
        ELSE 'Standard Contributor'
    END AS UserTier,
    (upa.TotalUpvotesGiven * 1.0 / NULLIF(upa.TotalDownvotesGiven, 0)) AS UpvoteDownvoteRatio,
    LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
    CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Network Site'
        ELSE 'External Site'
    END AS WebsiteType
FROM UserPostActivity upa
LEFT JOIN Users u ON upa.UserId = u.Id
WHERE upa.TotalPosts > 10
ORDER BY upa.TotalUpvotesGiven DESC, upa.TotalPosts DESC
LIMIT 100;