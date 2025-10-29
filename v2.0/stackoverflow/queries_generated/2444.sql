-- {"query": "2444.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1534} 

WITH RecursivePostsCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        0 AS Level,
        ARRAY[p.Id] AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1
    
    UNION ALL
    
    SELECT
        c.Id,
        c.PostTypeId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.Title,
        r.Level + 1,
        r.Path || c.Id
    FROM Posts c
    INNER JOIN RecursivePostsCTE r ON c.ParentId = r.Id
    WHERE c.PostTypeId IN (2, 7) -- Answers and WikiPlaceholder as children
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostVotesAggregated AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite') AS Favorites,
        COUNT(*) FILTER (WHERE vt.Name IN ('Close', 'Deletion')) AS NegativeVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
LatestPostHistory AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.UserId AS EditorUserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS HistoryDate,
        ph.Comment
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    ORDER BY ph.PostId, ph.CreationDate DESC
),
QuestionDuplicates AS (
    SELECT
        pl.PostId,
        COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount,
        STRING_AGG(DISTINCT p2.Title, '; ' ORDER BY p2.CreationDate) AS DuplicateTitles
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE lt.Name = 'Duplicate'
    GROUP BY pl.PostId
),
RecentCommentsCounts AS (
    SELECT
        c.PostId,
        COUNT(*) AS RecentCommentsCount
    FROM Comments c
    WHERE c.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY c.PostId
),
RankedPosts AS (
    SELECT
        rp.Id,
        rp.Level,
        rp.Path,
        rp.PostTypeId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.TotalBadges,
        pv.UpVotes,
        pv.DownVotes,
        pv.Favorites,
        pv.NegativeVotes,
        lh.HistoryTypeName AS LastEditType,
        lh.EditorDisplayName,
        lh.HistoryDate AS LastEditDate,
        qd.DuplicateCount,
        qd.DuplicateTitles,
        rc.RecentCommentsCount,
        u.Reputation,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Location,
        u.AboutMe
    FROM RecursivePostsCTE rp
    LEFT JOIN Users u ON rp.OwnerUserId = u.Id
    LEFT JOIN UserBadgeCounts b ON u.Id = b.UserId
    LEFT JOIN PostVotesAggregated pv ON rp.Id = pv.PostId
    LEFT JOIN LatestPostHistory lh ON rp.Id = lh.PostId
    LEFT JOIN QuestionDuplicates qd ON rp.Id = qd.PostId
    LEFT JOIN RecentCommentsCounts rc ON rp.Id = rc.PostId
    WHERE rp.PostTypeId = 1 -- we focus on questions to benchmark complex querying
),
WindowedStats AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY Level ORDER BY Score DESC, ViewCount DESC) AS ScoreRankWithinLevel,
        ROW_NUMBER() OVER (ORDER BY COALESCE(Favorites,0) DESC, Score DESC) AS FavoriteRankOverall,
        AVG(Score) OVER (PARTITION BY Level) AS AvgScorePerLevel,
        COUNT(*) OVER () AS TotalPosts,
        COUNT(CASE WHEN DuplicateCount > 0 THEN 1 END) OVER () AS PostsWithDuplicates
    FROM RankedPosts
)
SELECT
    ws.Id AS QuestionId,
    ws.Title,
    ws.CreationDate,
    ws.Score,
    ws.ViewCount,
    ws.UpVotes,
    ws.DownVotes,
    ws.Favorites,
    ws.NegativeVotes,
    ws.GoldBadges,
    ws.SilverBadges,
    ws.BronzeBadges,
    ws.TotalBadges,
    ws.LastEditType,
    ws.EditorDisplayName,
    ws.LastEditDate,
    COALESCE(ws.DuplicateCount, 0) AS DuplicateCount,
    ws.DuplicateTitles,
    COALESCE(ws.RecentCommentsCount, 0) AS RecentCommentsCount,
    ws.DisplayName AS OwnerDisplayName,
    ws.Reputation,
    ws.Location,
    ws.AboutMe,
    ws.Level,
    ws.ScoreRankWithinLevel,
    ws.FavoriteRankOverall,
    ws.AvgScorePerLevel,
    ws.TotalPosts,
    ws.PostsWithDuplicates,
    CASE
        WHEN ws.LastEditDate IS NULL THEN 'Never Edited'
        WHEN ws.LastEditDate < ws.CreationDate + INTERVAL '1 day' THEN 'Edited Quickly'
        ELSE 'Edited Later'
    END AS EditTimingCategory,
    -- Complex string expression and NULL logic combined
    COALESCE(NULLIF(TRIM(ws.AboutMe), ''), 'No about me available') || 
        ' | Location: ' || COALESCE(NULLIF(ws.Location, ''), 'Unknown') ||
        ' | Owner since: ' || TO_CHAR(ws.UserCreationDate, 'YYYY-MM-DD') AS OwnerSummary
FROM WindowedStats ws
WHERE ws.Score >= (
    SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score)
    FROM Posts
    WHERE PostTypeId = 1
) -- Only top 25% scored questions
AND COALESCE(ws.DuplicateCount, 0) = 0 -- exclude duplicates
AND ws.RecentCommentsCount > 5 -- active discussions
ORDER BY ws.FavoriteRankOverall
LIMIT 100;
