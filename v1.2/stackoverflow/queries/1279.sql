WITH RECURSIVE RecursiveCTE AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Tags,
        p.CreationDate,
        rnk.RowNum
    FROM posts p
    LEFT JOIN (
        SELECT
            Id,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, CreationDate ASC) as RowNum
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
    ) rnk ON p.Id = rnk.Id
    WHERE p.PostTypeId IN (1, 2)

    UNION ALL

    SELECT
        cte.PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Tags,
        p.CreationDate,
        cte.RowNum
    FROM Posts p
    JOIN RecursiveCTE cte ON p.ParentId = cte.PostId
    WHERE p.PostTypeId = 2
),
PostVotes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Close' THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(v.BountyAmount) AS TotalBounty
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id AND pht.Name = 'Post Closed'
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId, crt.Name
),
TagExplode AS (
    SELECT
        p.Id AS QuestionId,
        unnest(string_to_array(trim(BOTH '<>' FROM p.Tags), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
HighlyViewedAccepted AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        u.DisplayName AS OwnerName,
        v.UpVotes,
        v.DownVotes,
        v.CloseVotes,
        v.TotalBounty,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.UserId IS NOT NULL) AS QuestionCommentCount,
        (SELECT AVG(COALESCE(Score,0)) FROM Posts ans WHERE ans.ParentId = q.Id) AS AvgAnswerScore,
        qc.CloseReason,
        qc.CloseCount,
        q.ViewCount
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN PostVotes v ON q.Id = v.PostId
    LEFT JOIN UserBadgeSummary bs ON q.OwnerUserId = bs.UserId
    LEFT JOIN QuestionCloseReasons qc ON q.Id = qc.PostId
    WHERE
        q.PostTypeId = 1
        AND q.ViewCount > 10000
        AND a.Score > 0
        AND COALESCE(v.CloseVotes,0) < 3
),
DuplicateQuestions AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
QuestionRanksWithDuplicates AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.ViewCount,
        q.AnswerScore,
        q.OwnerName,
        q.UpVotes,
        q.DownVotes,
        q.TotalBounty,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.QuestionCommentCount,
        q.AvgAnswerScore,
        q.CloseReason,
        q.CloseCount,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerName ORDER BY q.ViewCount DESC, q.AnswerScore DESC) AS OwnerRank,
        (CASE WHEN dq.PostId IS NOT NULL THEN TRUE ELSE FALSE END) AS IsDuplicate
    FROM HighlyViewedAccepted q
    LEFT JOIN DuplicateQuestions dq ON q.QuestionId = dq.PostId
)
SELECT
    qr.OwnerName,
    qr.Title,
    qr.ViewCount,
    qr.AnswerScore,
    qr.UpVotes,
    qr.DownVotes,
    qr.TotalBounty,
    qr.GoldBadges,
    qr.SilverBadges,
    qr.BronzeBadges,
    qr.QuestionCommentCount,
    ROUND(CAST(qr.AvgAnswerScore AS NUMERIC), 2) AS AverageAnswerScore,
    COALESCE(qr.CloseReason, 'Open') AS CloseReason,
    qr.CloseCount,
    CASE
        WHEN qr.IsDuplicate THEN 'Yes'
        ELSE 'No'
    END AS DuplicateStatus,
    qr.OwnerRank,
    CASE
        WHEN qr.Title IS NOT NULL THEN SUBSTRING(qr.Title FROM 1 FOR 100) || COALESCE(' (' || qr.OwnerName || ')', '')
        ELSE COALESCE(qr.OwnerName, 'Unknown Owner')
    END AS TitleSnippet
FROM QuestionRanksWithDuplicates qr
WHERE qr.OwnerRank <= 5
ORDER BY qr.OwnerName, qr.OwnerRank;