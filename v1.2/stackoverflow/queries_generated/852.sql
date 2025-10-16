-- {"query": "852.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1643} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        rh.Level + 1,
        rh.Path || ' > ' || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy rh ON t2.Id > rh.Id AND t2.IsModeratorOnly = 0 AND t2.Count > rh.Count / 2
    WHERE rh.Level < 3
),
UserPostAggregate AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgScorePerPost,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass,
        MAX(b.Date) AS LastBadgeDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation >= 1000
    GROUP BY u.Id, u.DisplayName
),
RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS NextHighestScore,
        p.Tags,
        p.Title,
        p.ViewCount,
        p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
TopPostsWithComments AS (
    SELECT 
        rp.*,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCount,
        (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = rp.Id) AS AvgCommentScore,
        CASE 
            WHEN rp.Tags IS NOT NULL THEN array_to_string(string_to_array(trim(both '<>' FROM rp.Tags), '><'), ', ')
            ELSE NULL 
        END AS ParsedTags
    FROM RankedPosts rp
    WHERE rp.PostRank <= 3
),
UserCloseVotes AS (
    SELECT 
        ph.UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 12) AS DeleteVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 13) AS UndeleteVotes
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
FinalUserStats AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.TotalPosts,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.TotalPostScore,
        upa.AvgScorePerPost,
        upa.BadgeCount,
        upa.HighestBadgeClass,
        upa.LastBadgeDate,
        upa.LastPostDate,
        COALESCE(ucv.CloseVotes,0) AS CloseVotes,
        COALESCE(ucv.ReopenVotes,0) AS ReopenVotes,
        COALESCE(ucv.DeleteVotes,0) AS DeleteVotes,
        COALESCE(ucv.UndeleteVotes,0) AS UndeleteVotes,
        (upa.TotalPostScore::float / NULLIF(upa.TotalPosts,0)) + 
        (0.5 * COALESCE(ucv.CloseVotes,0)) - 
        (0.3 * COALESCE(ucv.DeleteVotes,0)) AS InfluenceScore
    FROM UserPostAggregate upa
    LEFT JOIN UserCloseVotes ucv ON ucv.UserId = upa.UserId
),
UserTopPosts AS (
    SELECT 
        fus.UserId,
        fus.DisplayName,
        tpc.Id AS PostId,
        tpc.PostTypeId,
        tpc.CreationDate,
        tpc.Score,
        tpc.NextHighestScore,
        tpc.ParsedTags,
        tpc.Title,
        tpc.ViewCount,
        tpc.FavoriteCount,
        tpc.CommentCount,
        tpc.AvgCommentScore,
        ROW_NUMBER() OVER (PARTITION BY fus.UserId ORDER BY tpc.Score DESC) AS UserPostRank
    FROM FinalUserStats fus
    JOIN TopPostsWithComments tpc ON fus.UserId = tpc.OwnerUserId
    WHERE fus.InfluenceScore > 50
),
UserPostDifferences AS (
    SELECT 
        utp.UserId,
        utp.DisplayName,
        utp.PostId,
        utp.PostTypeId,
        utp.CreationDate,
        utp.Score,
        utp.NextHighestScore,
        utp.ParsedTags,
        utp.Title,
        utp.ViewCount,
        utp.FavoriteCount,
        utp.CommentCount,
        utp.AvgCommentScore,
        utp.UserPostRank,
        COALESCE(utp.Score - utp.NextHighestScore, utp.Score) AS ScoreDifference,
        LENGTH(utp.Title) - LENGTH(REPLACE(utp.Title, ' ', '')) + 1 AS TitleWordCount,
        CASE WHEN utp.ParsedTags IS NOT NULL THEN array_length(string_to_array(utp.ParsedTags, ', '), 1) ELSE 0 END AS TagCount,
        CASE WHEN utp.CommentCount IS NULL THEN 0 ELSE utp.CommentCount END + COALESCE(utp.AvgCommentScore, 0) AS CommentInfluence
    FROM UserTopPosts utp
)
SELECT 
    fud.UserId,
    fud.DisplayName,
    fud.PostId,
    fud.PostTypeId,
    fud.CreationDate,
    fud.Score,
    fud.ScoreDifference,
    fud.TitleWordCount,
    fud.TagCount,
    fud.CommentCount,
    fud.AvgCommentScore,
    fud.CommentInfluence,
    f.InfluenceScore,
    CASE 
        WHEN fud.Score > 100 THEN 'High Scorer'
        WHEN fud.Score BETWEEN 50 AND 100 THEN 'Medium Scorer'
        ELSE 'Low Scorer'
    END AS ScoreCategory,
    CASE 
        WHEN fud.TagCount = 0 THEN 'Untagged'
        WHEN fud.TagCount BETWEEN 1 AND 3 THEN 'Lightly Tagged'
        ELSE 'Heavily Tagged'
    END AS TagCategory,
    CONCAT(
        LEFT(fud.Title, 30),
        CASE WHEN LENGTH(fud.Title) > 30 THEN '...' ELSE '' END
    ) AS ShortTitle,
    COALESCE(fud.ParsedTags, 'No Tags') AS TagsList
FROM UserPostDifferences fud
JOIN FinalUserStats f ON f.UserId = fud.UserId
WHERE fud.UserPostRank <= 2 AND f.InfluenceScore > 75
ORDER BY f.InfluenceScore DESC, fud.ScoreDifference DESC, fud.PostId
LIMIT 100;
