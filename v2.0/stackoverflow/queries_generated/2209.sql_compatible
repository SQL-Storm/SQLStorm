WITH RECURSIVE RecursiveBadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class

    UNION ALL

    SELECT 
        rbc.UserId,
        rbc.Class,
        rbc.BadgeCount
    FROM RecursiveBadgeCounts rbc
    WHERE rbc.BadgeCount > 0
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        AVG(COALESCE(p.Score, 0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        ARRAY_AGG(DISTINCT SUBSTRING(p.Tags FROM '<([^>]+)>')) AS TagArray
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
LatestPostComments AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        c.Id AS CommentId,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY c.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
),
DuplicationLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
),
UserActivityRanked AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopActiveUsers AS (
    SELECT 
        UserId, DisplayName, TotalPosts, ActivityRank
    FROM UserActivityRanked
    WHERE ActivityRank <= 10
),
CorrelatedAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        (
            SELECT COUNT(*) 
            FROM Posts a 
            WHERE a.ParentId = q.Id 
              AND a.Score > (SELECT AVG(score) FROM Posts WHERE ParentId = q.Id)
        ) AS HighScoreAnswerCount
    FROM Posts q
    WHERE q.PostTypeId = 1
),
ComplexFilteredPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS UserPostRank,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Open'
        END AS PostStatus,
        ARRAY_LENGTH(STRING_TO_ARRAY(COALESCE(p.Tags, ''), '><'), 1) AS TagCount,
        EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        ) AS WasEverClosed
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
      AND p.Score > 5 
      AND p.ViewCount > 1000
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%')
),
FinalSet AS (
    SELECT 
        cfp.Id AS PostId,
        cfp.Title,
        cfp.Score,
        cfp.ViewCount,
        cfp.FavoriteCount,
        cfp.OwnerName,
        cfp.UserPostRank,
        cfp.PostStatus,
        cfp.TagCount,
        cfp.WasEverClosed,
        COALESCE(ca.HighScoreAnswerCount, 0) AS HighScoreAnswerCount,
        (
            SELECT COUNT(DISTINCT b.Id) 
            FROM Badges b 
            WHERE b.UserId = (
                SELECT OwnerUserId FROM Posts WHERE Id = cfp.Id
            ) AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT COUNT(DISTINCT ph.Id) 
            FROM PostHistory ph 
            WHERE ph.PostId = cfp.Id AND ph.PostHistoryTypeId IN (4,5,6)
        ) AS EditCount,
        (
            SELECT COUNT(DISTINCT v.Id) 
            FROM Votes v 
            WHERE v.PostId = cfp.Id AND v.VoteTypeId = 2
        ) AS UpVotes,
        (
            SELECT COUNT(DISTINCT v.Id) 
            FROM Votes v 
            WHERE v.PostId = cfp.Id AND v.VoteTypeId = 3
        ) AS DownVotes,
        (
            SELECT STRING_AGG(DISTINCT lt.Name, ', ') 
            FROM PostLinks pl 
            JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId 
            WHERE pl.PostId = cfp.Id
        ) AS LinkTypesPresent
    FROM ComplexFilteredPosts cfp
    LEFT JOIN CorrelatedAnswers ca ON ca.QuestionId = cfp.Id
)
SELECT
    fs.PostId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.FavoriteCount,
    fs.OwnerName,
    fs.UserPostRank,
    fs.PostStatus,
    fs.TagCount,
    fs.WasEverClosed,
    fs.HighScoreAnswerCount,
    fs.GoldBadges,
    fs.EditCount,
    fs.UpVotes,
    fs.DownVotes,
    fs.LinkTypesPresent,
    CASE 
        WHEN fs.EditCount > 5 THEN CONCAT('Highly Edited: ', fs.Title)
        WHEN fs.WasEverClosed THEN CONCAT('Reopened? ', COALESCE(fs.Title, 'No Title'))
        ELSE UPPER(COALESCE(fs.Title, 'Untitled'))
    END AS TitleDisplay,
    SUM(fs.Score) OVER (PARTITION BY fs.OwnerName ORDER BY fs.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUserScore
FROM FinalSet fs
WHERE fs.GoldBadges >= 1 OR fs.HighScoreAnswerCount > 2
ORDER BY fs.GoldBadges DESC NULLS LAST, fs.HighScoreAnswerCount DESC, fs.Score DESC
LIMIT 100;