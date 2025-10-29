WITH RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.ViewCount, 0) AS TotalViews,
        u.Reputation AS OwnerReputation,
        u.DisplayName AS OwnerDisplayName,
        p.Id AS PostId,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC) AS rn
    FROM Tags t
    LEFT JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Id < 1000
),
TopTagPosts AS (
    SELECT
        TagId,
        TagName,
        PostId,
        AnswerCount,
        TotalViews,
        OwnerReputation,
        OwnerDisplayName
    FROM RecursiveTagCounts
    WHERE rn <= 5
),
LatestCloseReasons AS (
    SELECT ph.PostId,
           crt.Name AS CloseReasonName,
           ph.CreationDate
    FROM (
        SELECT ph.*,
               ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
          AND ph.PostId IS NOT NULL
    ) ph
    INNER JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.rn = 1
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    INNER JOIN Users u ON u.Id = b.UserId
    GROUP BY b.UserId, u.DisplayName
),
PostVoteAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId
),
AnswerWithAcceptedFlag AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
    FROM Posts a
    INNER JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
AnswerRankings AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Score,
        a.IsAccepted,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.Id ASC) AS ScoreRank
    FROM AnswerWithAcceptedFlag a
),
FinalPostDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        COALESCE(pv.UpVotes, 0) AS UpVotes,
        COALESCE(pv.DownVotes, 0) AS DownVotes,
        COALESCE(pv.TotalBounty, 0) AS TotalBounty,
        lcr.CloseReasonName,
        CASE WHEN lcr.CloseReasonName IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PopularityRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN UserBadgeSummary us ON us.UserId = p.OwnerUserId
    LEFT JOIN PostVoteAggregates pv ON pv.PostId = p.Id
    LEFT JOIN LatestCloseReasons lcr ON lcr.PostId = p.Id
    WHERE p.PostTypeId = 1
)
SELECT fpd.Id AS QuestionId,
       fpd.Title,
       fpd.CreationDate,
       fpd.Score,
       fpd.ViewCount,
       fpd.Tags,
       fpd.OwnerName,
       fpd.OwnerReputation,
       fpd.GoldBadges,
       fpd.SilverBadges,
       fpd.BronzeBadges,
       fpd.UpVotes,
       fpd.DownVotes,
       fpd.TotalBounty,
       fpd.IsClosed,
       fpd.CloseReasonName,
       COALESCE(ans.AnswerCount, 0) AS TotalAnswers,
       COALESCE(accepted.AnswerId, NULL) AS AcceptedAnswerId,
       accepted.Score AS AcceptedAnswerScore,
       top5.TopAnswers,
       ttp.TagName,
       ttp.OwnerDisplayName AS TopAnswerOwner,
       ttp.OwnerReputation AS TopAnswerOwnerReputation,
       ttp.AnswerCount AS TagAnswerCount,
       ttp.TotalViews AS TagViewCount
FROM FinalPostDetails fpd
LEFT JOIN (
    SELECT ParentId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
) ans ON ans.ParentId = fpd.Id
LEFT JOIN AnswerRankings accepted ON accepted.QuestionId = fpd.Id AND accepted.IsAccepted = 1
LEFT JOIN (
    SELECT
        a.ParentId,
        STRING_AGG('AnswerId:' || a.Id || ' Score:' || a.Score || ' IsAccepted:' || a.IsAccepted, '; ' ORDER BY a.Score DESC) AS TopAnswers
    FROM AnswerWithAcceptedFlag a
    GROUP BY a.ParentId
) top5 ON top5.ParentId = fpd.Id
LEFT JOIN TopTagPosts ttp ON ttp.PostId = fpd.Id
WHERE fpd.PopularityRank <= 100
UNION ALL
SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerReputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS UpVotes,
    0 AS DownVotes,
    0 AS TotalBounty,
    FALSE AS IsClosed,
    NULL AS CloseReasonName,
    0 AS TotalAnswers,
    NULL AS AcceptedAnswerId,
    NULL AS AcceptedAnswerScore,
    NULL AS TopAnswers,
    NULL AS TagName,
    NULL AS TopAnswerOwner,
    NULL AS TopAnswerOwnerReputation,
    0 AS TagAnswerCount,
    0 AS TagViewCount
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.Id NOT IN (SELECT Id FROM FinalPostDetails)
ORDER BY Score DESC
LIMIT 10;