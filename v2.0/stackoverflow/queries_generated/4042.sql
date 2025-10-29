-- {"query": "4042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1504} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 6) -- Edit Title, Edit Tags
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
),
TagSpecificMetrics AS (
    SELECT
        p.Id AS PostId,
        t.TagName,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        RANK() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) as RankByScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate ASC) as FirstPostSequence
    FROM Posts p
    CROSS JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    WHERE p.PostTypeId IN (1, 2) AND p.Tags IS NOT NULL
)
SELECT
    u.DisplayName AS UserName,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    COALESCE(ure.TotalQuestions, 0) AS UserQuestions,
    COALESCE(ure.TotalAnswers, 0) AS UserAnswers,
    COALESCE(ure.TotalComments, 0) AS UserComments,
    COALESCE(ure.TotalUpVotes, 0) AS UserUpVotes,
    COALESCE(ure.TotalDownVotes, 0) AS UserDownVotes,
    COALESCE(ure.TotalFavorites, 0) AS UserFavorites,
    rp.Title AS MostRecentPostTitle,
    rp.CreationDate AS MostRecentEditDate,
    rp.Comment AS MostRecentEditComment,
    tsm.TagName,
    tsm.PostType,
    tsm.Score AS TagPostScore,
    tsm.ViewCount AS TagPostViewCount,
    tsm.AnswerCount AS TagPostAnswerCount,
    tsm.FavoriteCount AS TagPostFavoriteCount,
    tsm.RankByScore,
    tsm.FirstPostSequence,
    CASE
        WHEN u.Views > 10000 THEN 'High Traffic User'
        WHEN u.Reputation > 50000 THEN 'High Reputation User'
        ELSE 'Standard User'
    END AS UserCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    COUNT(DISTINCT ph_close.PostId) AS ClosedPostsCount,
    SUM(CASE WHEN u.DownVotes > u.UpVotes THEN 1 ELSE 0 END) AS MoreDownThanUpVotes,
    CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
    END AS WebsiteType,
    (
        SELECT COUNT(DISTINCT p_linked.Id)
        FROM PostLinks pl
        JOIN Posts p_linked ON pl.PostId = p_linked.Id
        WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate links
    ) AS DuplicateLinksToThisPost
FROM Users u
LEFT JOIN UserPostEngagement ure ON u.Id = ure.UserId
LEFT JOIN RankedPostEdits rp ON u.Id = rp.UserId AND rp.rn = 1
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Focusing on questions for tag metrics join
LEFT JOIN TagSpecificMetrics tsm ON p.Id = tsm.PostId
LEFT JOIN PostHistory ph_close ON u.Id = ph_close.UserId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
WHERE u.DisplayName IS NOT NULL AND u.DisplayName NOT LIKE '%[deleted]%' AND u.Id > 1000 -- Exclude system users and focus on active users
GROUP BY
    u.DisplayName,
    u.Location,
    ure.TotalQuestions,
    ure.TotalAnswers,
    ure.TotalComments,
    ure.TotalUpVotes,
    ure.TotalDownVotes,
    ure.TotalFavorites,
    rp.Title,
    rp.CreationDate,
    rp.Comment,
    tsm.TagName,
    tsm.PostType,
    tsm.Score,
    tsm.ViewCount,
    tsm.AnswerCount,
    tsm.FavoriteCount,
    tsm.RankByScore,
    tsm.FirstPostSequence,
    u.Views,
    u.Reputation,
    u.WebsiteUrl,
    u.UpVotes,
    u.DownVotes
HAVING COUNT(DISTINCT ph_close.PostId) < ure.TotalQuestions * 0.1 -- Less than 10% of their questions closed
ORDER BY u.Reputation DESC, u.CreationDate ASC
LIMIT 1000;
