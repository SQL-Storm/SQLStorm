WITH RecursiveBadgeAgg AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        b.Class,
        b.Name AS BadgeName,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class, b.Date DESC) AS rn
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
), FilteredBadges AS (
    SELECT UserId, Reputation, CreationDate, DisplayName, Class, BadgeName
    FROM RecursiveBadgeAgg
    WHERE rn <= 3
), UserTopPosts AS (
    SELECT 
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(NULLIF(TRIM(p.Title), ''), '<no title>') AS Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rk
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1,2)
), BestPostsBase AS (
    SELECT UserId, PostId, PostTypeId, Score, ViewCount, Title, Tags
    FROM UserTopPosts
    WHERE rk <= 2
), CloseVotesImportantCloseReasonIds AS (
    SELECT prt.Id, prt.Name
    FROM CloseReasonTypes prt
    WHERE prt.Name ILIKE '%duplicate%' OR prt.Name ILIKE '%off-topic%'
), PostCloseVotes AS (
    SELECT ph.PostId, CAST(ph.Comment AS INTEGER) AS CloseReasonId, COUNT(*) AS CloseVoteCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.Comment ~ '^[0-9]+$'
      AND CAST(ph.Comment AS INTEGER) IN (SELECT Id FROM CloseVotesImportantCloseReasonIds)
    GROUP BY ph.PostId, CAST(ph.Comment AS INTEGER)
), QuestionsWithCloseVotes AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        SUM(pcvcv.CloseVoteCount) FILTER (WHERE pcvcv.CloseReasonId IS NOT NULL) AS TotalImportantCloseVotes,
        COUNT(DISTINCT pcvcv.CloseReasonId) FILTER (WHERE pcvcv.CloseReasonId IS NOT NULL) AS CloseReasonKinds,
        MAX(CASE WHEN pcvcv.CloseReasonId IN (
                SELECT Id FROM CloseVotesImportantCloseReasonIds WHERE Name ILIKE '%duplicate%')
            THEN 1 ELSE 0 END) AS HasDuplicateCloseVotes
    FROM Posts p
    LEFT JOIN PostCloseVotes pcvcv ON pcvcv.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId
), PositivityScoreWindow AS (
    SELECT 
        v.UserId,
        CAST(COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS NUMERIC) /
            NULLIF(CAST(COUNT(*) FILTER (WHERE vt.Name IN ('DownMod','UpMod')) AS NUMERIC), 0) AS PositivityRatio
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT DISTINCT
    fb.UserId,
    bp.PostTypeId,
    fb.Reputation,
    fb.CreationDate,
    fb.DisplayName,
    fb.Class AS BadgeClass,
    fb.BadgeName,
    bp.Score,
    bp.ViewCount,
    bp.Title,
    COALESCE(qc.TotalImportantCloseVotes, 0) AS TotalImportantCloseVotes,
    COALESCE(qc.CloseReasonKinds, 0) AS CloseReasonKinds,
    COALESCE(qc.HasDuplicateCloseVotes, 0) AS HasDuplicateCloseVotes,
    pscore.PositivityRatio
FROM FilteredBadges fb
LEFT JOIN BestPostsBase bp ON bp.UserId = fb.UserId
LEFT JOIN QuestionsWithCloseVotes qc ON qc.OwnerUserId = fb.UserId
LEFT JOIN PositivityScoreWindow pscore ON pscore.UserId = fb.UserId
ORDER BY fb.UserId, bp.Score DESC, bp.ViewCount DESC;